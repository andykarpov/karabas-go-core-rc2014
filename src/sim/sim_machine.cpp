// sim_machine.cpp: rc2014_machine on verilator with the board SRAM (4 MB, the read data registered
// as rc2014_mem does) and the terminal line (115200 8N1 both ways): what the machine sends on
// tx_a goes to stdout, the --key text is typed into rx_a.
//
//   --profile N        0 RomWBW 512K, 1 Classic, 2 Mini
//   --serial N         0 SIO/2, 1 ACIA (Classic / RomWBW; Mini is always ACIA)
//   --turbo            Z80 at 14.7456 MHz
//   --rom ADDR:FILE    load FILE into the SRAM at ADDR (repeat)
//   --ms N             simulated time (ms)
//   --key MS:TEXT      type TEXT from MS on (\r = CR, one character every 2 ms; repeat)
//   --mem-lat N        clocks from mem_a to mem_rdata (1 = rc2014_mem with a 0 ns SRAM; the board: 2)
//   --cf FILE          the CF image (device 0, the file mounter of kg_mcu2 modelled: a sector in ~40 us)
//   --trace-io         print every I/O access (port, data) to stderr
//   --fill-random      the SRAM random before the ROMs are loaded (as after power on; give it first)
//   --usb MS:TEXT      bytes into SIO/2 channel B (the USB serial port, as kg_mcu2 port 0); its
//                      output goes to stderr as [B ...] at the end
//   --tms              Console = TMS9918: port 00 reads 80, the keyboard is the 8242
//   --kbd MS:TEXT      type TEXT on the PS/2 keyboard of the 8242 (set 2 make / break, a key every 30 ms)
//   --ppm FILE         the TMS9918 picture at the end (256 x 192, as msx_video takes it) to FILE
//   --joy1 N / --joy2 N  joystick bits (0 up 1 down 2 left 3 right 4 fire 1 5 fire 2)
// TRACE_MEM=N (env): the first N memory cycles (address at MREQ, the data then is not the one read)
#include "Vrc2014_machine.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <deque>

static const double CLK_HZ = 50e6;
static const double BIT_CLK = CLK_HZ / 115200.0;

struct Key { double ms; std::string text; };

// PS/2 set 2 make codes of the characters --kbd types (0: none); shift for upper case / symbols
static int ps2_code(char c, int *shift) {
	static const char *lo = "abcdefghijklmnopqrstuvwxyz";
	static const uint8_t lc[26] = { 0x1C,0x32,0x21,0x23,0x24,0x2B,0x34,0x33,0x43,0x3B,0x42,0x4B,0x3A,
		0x31,0x44,0x4D,0x15,0x2D,0x1B,0x2C,0x3C,0x2A,0x1D,0x22,0x35,0x1A };
	static const uint8_t dg[10] = { 0x45,0x16,0x1E,0x26,0x25,0x2E,0x36,0x3D,0x3E,0x46 };
	*shift = 0;
	if (c >= 'a' && c <= 'z') return lc[strchr(lo, c) - lo];
	if (c >= 'A' && c <= 'Z') { *shift = 1; return lc[c - 'A']; }
	if (c >= '0' && c <= '9') return dg[c - '0'];
	switch (c) {
	case ' ': return 0x29; case '\r': return 0x5A; case '.': return 0x49; case ',': return 0x41;
	case '-': return 0x4E; case '=': return 0x55; case '/': return 0x4A; case ';': return 0x4C;
	case ':': *shift = 1; return 0x4C; case '+': *shift = 1; return 0x55; case '*': *shift = 1; return 0x3E;
	case '?': *shift = 1; return 0x4A; case '"': *shift = 1; return 0x52;
	}
	return 0;
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	int profile = 0, serial = 0, turbo = 0, trace_io = 0, mem_lat = 1;
	FILE *cf = nullptr; uint64_t cf_size = 0;
	double ms = 100;
	std::vector<Key> keys, usb, kbd;
	int tms = 0, joy1 = 0, joy2 = 0;
	std::string ppm;
	static uint8_t mem[1 << 22];
	memset(mem, 0xFF, sizeof mem);
	for (int i = 1; i < argc; i++) {
		std::string a = argv[i];
		auto next = [&]() { return std::string(i + 1 < argc ? argv[++i] : ""); };
		if (a == "--profile") profile = atoi(next().c_str());
		else if (a == "--serial") serial = atoi(next().c_str());
		else if (a == "--turbo") turbo = 1;
		else if (a == "--ms") ms = atof(next().c_str());
		else if (a == "--trace-io") trace_io = 1;
		else if (a == "--mem-lat") mem_lat = atoi(next().c_str());
		else if (a == "--cf") {
			std::string f = next();
			cf = fopen(f.c_str(), "r+b");
			if (!cf) { perror(f.c_str()); return 1; }
			fseek(cf, 0, SEEK_END); cf_size = ftell(cf);
			fprintf(stderr, "cf %s: %llu bytes\n", f.c_str(), (unsigned long long)cf_size);
		}
		else if (a == "--fill-random") { unsigned x = 12345; for (size_t k = 0; k < sizeof mem; k++) { x = x * 1103515245u + 12345u; mem[k] = x >> 16; } }
		else if (a == "--rom") {
			std::string v = next();
			size_t c = v.find(':');
			unsigned long addr = strtoul(v.substr(0, c).c_str(), nullptr, 0);
			FILE *f = fopen(v.substr(c + 1).c_str(), "rb");
			if (!f) { perror(v.c_str()); return 1; }
			size_t n = fread(mem + addr, 1, sizeof mem - addr, f);
			fclose(f);
			fprintf(stderr, "rom %s: %zu bytes at 0x%06lx\n", v.substr(c + 1).c_str(), n, addr);
		}
		else if (a == "--tms") tms = 1;
		else if (a == "--ppm") ppm = next();
		else if (a == "--joy1") joy1 = atoi(next().c_str());
		else if (a == "--joy2") joy2 = atoi(next().c_str());
		else if (a == "--key" || a == "--usb" || a == "--kbd") {
			std::vector<Key> &dst = a == "--key" ? keys : a == "--usb" ? usb : kbd;
			std::string v = next();
			size_t c = v.find(':');
			std::string t, s = v.substr(c + 1);
			for (size_t k = 0; k < s.size(); k++) {
				if (s[k] == '\\' && k + 1 < s.size() && s[k + 1] == 'r') { t += '\r'; k++; }
				else t += s[k];
			}
			dst.push_back({ atof(v.substr(0, c).c_str()), t });
		}
	}

	Vrc2014_machine *m = new Vrc2014_machine;
	m->profile = profile;
	m->serial = serial;
	m->turbo = turbo;
	m->rx_a = 1;
	m->hold_a = 0;
	m->rxb_wr = 0;
	m->txb_full = 0;
	m->fp_sw = tms ? 0x80 : 0x00;
	m->joy1 = joy1;
	m->joy2 = joy2;
	m->kbd_wr = 0;
	m->reset = 1;
	m->power_reset = 1;
	m->cf_card = 0;
	m->ide_din = 0xFF;
	m->clk = 0;

	// the typed characters: (start clock, byte)
	std::deque<std::pair<uint64_t, uint8_t>> txq;
	for (auto &k : keys)
		for (size_t j = 0; j < k.text.size(); j++)
			txq.push_back({ (uint64_t)((k.ms + 2.0 * j) * CLK_HZ / 1000.0), (uint8_t)k.text[j] });

	// channel B bytes and the PS/2 bytes: (not before clock, byte)
	std::deque<std::pair<uint64_t, uint8_t>> usbq, kbdq;
	for (auto &k : usb)
		for (size_t j = 0; j < k.text.size(); j++)
			usbq.push_back({ (uint64_t)(k.ms * CLK_HZ / 1000.0), (uint8_t)k.text[j] });
	for (auto &k : kbd)
		for (size_t j = 0; j < k.text.size(); j++) {
			int sh, code = ps2_code(k.text[j], &sh);
			if (!code) continue;
			uint64_t t0 = (uint64_t)((k.ms + 30.0 * j) * CLK_HZ / 1000.0);
			if (sh) kbdq.push_back({ t0, 0x12 });
			kbdq.push_back({ t0, (uint8_t)code });
			kbdq.push_back({ t0 + 500000, 0xF0 });
			kbdq.push_back({ t0 + 500000, (uint8_t)code });
			if (sh) { kbdq.push_back({ t0 + 500000, 0xF0 }); kbdq.push_back({ t0 + 500000, 0x12 }); }
		}
	uint64_t kbd_next = 0;
	std::string b_out;
	// the TMS picture (msx_video write side) and the YM2149 activity
	static uint8_t fb[192][256];
	int hor_d = 0, vert_d = 0, fx = 0, fy = 0;
	long psg_changes = 0; int psg_last = -1;

	uint64_t end = (uint64_t)(ms * CLK_HZ / 1000.0);
	uint8_t rdata = 0xFF;
	// receiver of tx_a
	int rx_state = 0; double rx_t = 0; int rx_bit = 0; uint8_t rx_sh = 0;
	// sender into rx_a
	int tx_busy = 0; uint64_t tx_t0 = 0; uint16_t tx_frame = 0;
	int last_io = 0;
	long tx_edges = 0; int tx_last = 1;
	// the file mounter: 0 idle, 1 read (bytes out), 2 write (bytes in), then done
	int sd_state = 0; uint64_t sd_t = 0; uint32_t sd_lba = 0; uint8_t sd_buf[512]; int sd_i = 0;
	long sd_reads = 0, sd_writes = 0;
	// the RTC RAM of kg_mcu2 (rtc_mode 1, DS1307 BCD): 2026-11-19 (Thu) 12:34:56
	static uint8_t rtc[256] = { 0x56, 0x34, 0x12, 0x05, 0x19, 0x11, 0x26 };
	uint8_t rtc_q = 0;

	for (uint64_t t = 0; t < end && !Verilated::gotFinish(); t++) {
		if (t == 100) { m->reset = 0; m->power_reset = 0; }
		m->mem_rdata = rdata;
		m->clk = 1;
		m->eval();
		// the SRAM: read data registered (as rc2014_mem), writes while mem_wr
		static uint8_t pipe[8] = { 0xFF };
		for (int k = 7; k > 0; k--) pipe[k] = pipe[k - 1];
		pipe[0] = mem[m->mem_a & 0x3FFFFF];
		rdata = pipe[mem_lat - 1];
		if (m->mem_wr) mem[m->mem_a & 0x3FFFFF] = m->mem_wdata;

		// the RTC RAM: the seconds tick (BCD, as the firmware sets them), rtc_a -> rtc_do a clock later,
		// writes of the core
		if (t % 50000000 == 49999999) {
			uint8_t sec = rtc[0];
			sec = ((sec & 0x0F) == 9) ? (uint8_t)((sec & 0xF0) + 0x10) : (uint8_t)(sec + 1);
			if (sec >= 0x60) { sec = 0; rtc[1] = ((rtc[1] & 0x0F) == 9) ? (uint8_t)((rtc[1] & 0xF0) + 0x10) : (uint8_t)(rtc[1] + 1); }
			rtc[0] = sec;
		}
		m->rtc_do = rtc_q;
		rtc_q = rtc[m->rtc_a];
		if (m->rtc_cs && !m->rtc_wr_n) { rtc[m->rtc_a] = m->rtc_di; fprintf(stderr, "[rtc write %02x = %02x]\n", m->rtc_a, m->rtc_di); }

		// the file mounter of the CF (kg_mcu2 SDC_*): mount at 1 ms, then the requests
		m->img_mounted = 0;
		m->sdc_done = 0;
		m->sdc_byte_in_strobe = 0;
		if (cf && t == 50000) { m->img_mounted = 1; m->img_size = cf_size; }
		if (cf) {
			if (sd_state == 0 && (m->sdc_rd & 1)) {
				sd_lba = m->sdc_sector; m->sdc_busy = 1; sd_state = 1; sd_t = t + 1000; sd_i = 0; sd_reads++;
				memset(sd_buf, 0, 512);
				if ((uint64_t)sd_lba * 512 < cf_size) { fseek(cf, (long)sd_lba * 512, SEEK_SET); if (fread(sd_buf, 1, 512, cf) != 512) {} }
			}
			else if (sd_state == 0 && (m->sdc_wr & 1)) {
				sd_lba = m->sdc_sector; m->sdc_busy = 1; sd_state = 2; sd_t = t + 100; sd_i = 0; sd_writes++;
			}
			else if (sd_state == 1 && t >= sd_t) {
				// one byte every 4 clocks
				if (((t - sd_t) & 3) == 0) {
					m->sdc_byte_in_strobe = 1; m->sdc_byte_addr = sd_i; m->sdc_byte_in_data = sd_buf[sd_i];
					if (++sd_i == 512) { sd_state = 3; sd_t = t + 20; }
				}
			}
			else if (sd_state == 2 && t >= sd_t) {
				// write: address out, the data 3 clocks later (IMG_OUT_LATENCY)
				static int pend[4] = { -1, -1, -1, -1 };
				if (pend[3] >= 0) sd_buf[pend[3]] = m->sdc_byte_out_data;
				pend[3] = pend[2]; pend[2] = pend[1]; pend[1] = pend[0];
				pend[0] = sd_i < 512 ? sd_i : -1;
				if (sd_i < 512) { m->sdc_byte_addr = sd_i; sd_i++; }
				else if (pend[1] < 0 && pend[2] < 0 && pend[3] < 0) {
					if ((uint64_t)sd_lba * 512 < cf_size) { fseek(cf, (long)sd_lba * 512, SEEK_SET); fwrite(sd_buf, 1, 512, cf); }
					sd_state = 3; sd_t = t + 20;
				}
			}
			else if (sd_state == 3 && t >= sd_t) { m->sdc_done = 1; m->sdc_busy = 0; sd_state = 0; }
		}

		// channel B: a byte when the SIO takes one; its output collected
		m->rxb_wr = 0;
		if (!usbq.empty() && t >= usbq.front().first && m->rxb_ready) {
			m->rxb_data = usbq.front().second; m->rxb_wr = 1; usbq.pop_front();
		}
		if (m->txb_wr) b_out += (char)m->txb_data;
		// the PS/2 keyboard: a byte every 1 ms (about the PS/2 rate)
		m->kbd_wr = 0;
		if (!kbdq.empty() && t >= kbdq.front().first && t >= kbd_next) {
			m->kbd_code = kbdq.front().second; m->kbd_wr = 1; kbdq.pop_front(); kbd_next = t + 50000;
		}
		// the TMS picture
		if (m->vdp_ce_pix) {
			int h = m->vdp_hor_active, v = m->vdp_vert_active;
			if (v && !vert_d) fy = 0;
			if (h && !hor_d) fx = 0; else if (h) fx++;
			if (!h && hor_d && v) fy++;
			if (h && v && fy < 192 && fx < 256) fb[fy][fx] = m->vdp_col;
			hor_d = h; vert_d = v;
		}
		if (m->psg_sound != psg_last) { psg_changes++; psg_last = m->psg_sound; }

		// tx_a -> stdout
		int line = m->tx_a;
		if (line != tx_last) { tx_edges++; tx_last = line; }
		if (rx_state == 0 && !line) { rx_state = 1; rx_t = t + BIT_CLK * 1.5; rx_bit = 0; rx_sh = 0; }
		else if (rx_state == 1 && t >= (uint64_t)rx_t) {
			if (rx_bit < 8) { rx_sh |= (line & 1) << rx_bit; rx_bit++; rx_t += BIT_CLK; }
			else { putchar(rx_sh); fflush(stdout); rx_state = 2; rx_t += BIT_CLK * 0.5; }
		}
		else if (rx_state == 2 && line) rx_state = 0;

		// typed text -> rx_a
		if (!tx_busy && !txq.empty() && t >= txq.front().first) {
			tx_frame = (uint16_t)((1 << 9) | (txq.front().second << 1));
			txq.pop_front();
			tx_busy = 1; tx_t0 = t;
		}
		if (tx_busy) {
			int b = (int)((t - tx_t0) / BIT_CLK);
			if (b >= 10) { tx_busy = 0; m->rx_a = 1; }
			else m->rx_a = (tx_frame >> b) & 1;
		}

		if (getenv("TRACE_MEM")) {
			static int lm = 0; static long nmem = 0;
			int mr = (m->dbg >> 1) & 1;
			if (mr && !lm && nmem < atol(getenv("TRACE_MEM"))) { fprintf(stderr, "[%.4f] mem %04x di %02x\n", t * 1000.0 / CLK_HZ, m->cpu_a, rdata); nmem++; }
			lm = mr;
		}
		if (trace_io) {
			int io = m->dbg & 1;
			static int wr_seen = 0;
			if (io && !last_io) wr_seen = 0;
			if (io && m->cpu_wr && !wr_seen) { fprintf(stderr, "[%.3f ms] out %02x <- %02x\n", t * 1000.0 / CLK_HZ, m->cpu_a & 0xFF, m->cpu_do); wr_seen = 1; }
			if (!io && last_io && !wr_seen) fprintf(stderr, "[%.3f ms] in  %02x -> %02x\n", t * 1000.0 / CLK_HZ, m->cpu_a & 0xFF, m->cpu_di);
			last_io = io;
		}

		m->clk = 0;
		m->eval();
	}
	fprintf(stderr, "\n[end %.1f ms, tx_a edges %ld, cf reads %ld writes %ld, psg changes %ld]\n", ms, tx_edges, sd_reads, sd_writes, psg_changes);
	if (!b_out.empty()) fprintf(stderr, "[B %s]\n", b_out.c_str());
	if (!ppm.empty()) {
		static const uint8_t pal[16][3] = { {0,0,0},{0,0,0},{33,200,66},{94,220,120},{84,85,237},{125,118,252},
			{212,82,77},{66,235,245},{252,85,84},{255,121,120},{212,193,84},{230,206,128},{33,176,59},
			{201,91,186},{204,204,204},{255,255,255} };
		FILE *f = fopen(ppm.c_str(), "wb");
		fprintf(f, "P6\n256 192\n255\n");
		for (int y = 0; y < 192; y++) for (int x = 0; x < 256; x++) fwrite(pal[fb[y][x] & 15], 1, 3, f);
		fclose(f);
	}
	if (cf) fclose(cf);
	delete m;
	return 0;
}
