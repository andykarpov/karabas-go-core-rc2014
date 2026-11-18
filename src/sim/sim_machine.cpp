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
//   --trace-io         print every I/O access (port, data) to stderr
//   --fill-random      the SRAM random before the ROMs are loaded (as after power on; give it first)
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

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	int profile = 0, serial = 0, turbo = 0, trace_io = 0;
	double ms = 100;
	std::vector<Key> keys;
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
		else if (a == "--key") {
			std::string v = next();
			size_t c = v.find(':');
			std::string t, s = v.substr(c + 1);
			for (size_t k = 0; k < s.size(); k++) {
				if (s[k] == '\\' && k + 1 < s.size() && s[k + 1] == 'r') { t += '\r'; k++; }
				else t += s[k];
			}
			keys.push_back({ atof(v.substr(0, c).c_str()), t });
		}
	}

	Vrc2014_machine *m = new Vrc2014_machine;
	m->profile = profile;
	m->serial = serial;
	m->turbo = turbo;
	m->rx_a = 1;
	m->rx_b = 1;
	m->reset = 1;
	m->clk = 0;

	// the typed characters: (start clock, byte)
	std::deque<std::pair<uint64_t, uint8_t>> txq;
	for (auto &k : keys)
		for (size_t j = 0; j < k.text.size(); j++)
			txq.push_back({ (uint64_t)((k.ms + 2.0 * j) * CLK_HZ / 1000.0), (uint8_t)k.text[j] });

	uint64_t end = (uint64_t)(ms * CLK_HZ / 1000.0);
	uint8_t rdata = 0xFF;
	// receiver of tx_a
	int rx_state = 0; double rx_t = 0; int rx_bit = 0; uint8_t rx_sh = 0;
	// sender into rx_a
	int tx_busy = 0; uint64_t tx_t0 = 0; uint16_t tx_frame = 0;
	int last_io = 0;
	long tx_edges = 0; int tx_last = 1;

	for (uint64_t t = 0; t < end && !Verilated::gotFinish(); t++) {
		if (t == 100) m->reset = 0;
		m->mem_rdata = rdata;
		m->clk = 1;
		m->eval();
		// the SRAM: read data registered (as rc2014_mem), writes while mem_wr
		rdata = mem[m->mem_a & 0x3FFFFF];
		if (m->mem_wr) mem[m->mem_a & 0x3FFFFF] = m->mem_wdata;

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
	fprintf(stderr, "\n[end %.1f ms, tx_a edges %ld]\n", ms, tx_edges);
	delete m;
	return 0;
}
