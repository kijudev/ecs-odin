#include "harness.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fnmatch.h>
#include <vector>

#include "data.hpp"
#include "memory.hpp"

namespace bench {

namespace {

constexpr int MAX_SAMPLES = 30;
constexpr int MIN_SAMPLES = 5;
constexpr int WALL_CAP_SAMPLES = 3;
constexpr double MIN_TIMED_NS = 0.1e9;
constexpr double WALL_CAP_NS = 3e9;
constexpr double MIN_RUN_NS = 50e3;

double now_ns() {
    using namespace std::chrono;
    return double(duration_cast<nanoseconds>(steady_clock::now().time_since_epoch()).count());
}

double median(std::vector<double> values) {
    std::sort(values.begin(), values.end());
    size_t mid = values.size() / 2;
    return values.size() % 2 ? values[mid] : (values[mid - 1] + values[mid]) / 2;
}

struct Options {
    std::vector<int> sizes = {10'000, 100'000, 1'000'000};
    std::vector<std::string> patterns;
};

Options parse(int argc, char **argv) {
    Options options;

    for (int i = 1; i + 1 < argc; i += 2) {
        std::string flag = argv[i];
        std::string list = argv[i + 1];

        std::vector<std::string> items;
        for (size_t start = 0, comma; start <= list.size(); start = comma + 1) {
            comma = std::min(list.find(',', start), list.size());
            items.push_back(list.substr(start, comma - start));
        }

        if (flag == "--n") {
            options.sizes.clear();
            for (auto &item : items) options.sizes.push_back(std::atoi(item.c_str()));
        } else if (flag == "--case") {
            options.patterns = items;
        } else {
            std::fprintf(stderr, "unknown flag %s\n", flag.c_str());
            std::exit(1);
        }
    }

    return options;
}

bool matches(const Options &options, const std::string &id) {
    if (options.patterns.empty()) return true;
    for (auto &pattern : options.patterns)
        if (fnmatch(pattern.c_str(), id.c_str(), 0) == 0) return true;
    return false;
}

} // namespace

// >-------------------------------------------------------------------- Sampler

void Sampler::begin() {
    live = memory::live() - base;
    memory::reset_peak();
    start_ns = now_ns();
}

void Sampler::end(int64_t ops, int runs) {
    took_ns = now_ns() - start_ns;
    peak = memory::peak() - (base + live);
    this->runs = runs;
    ns_per_op = took_ns / double(ops * runs);
    timed = true;
}

// >------------------------------------------------------------------------ Run

int run(const char *lib, std::span<const Case> cases, int argc, char **argv) {
    Options options = parse(argc, argv);

    std::printf(
        "lib,group,case,n,median_ns_op,min_ns_op,mad_ns_op,samples,runs,live_bytes,peak_bytes,"
        "checksum\n");

    for (int n : options.sizes) {
        make_perm(n);

        for (auto &c : cases) {
            std::string id = c.group + "." + c.name;
            if (!matches(options, id)) continue;

            Sampler sampler;
            std::vector<double> ns_per_op;
            double checksum = 0, timed_ns = 0, wall_start = now_ns();

            for (int sample = 0;; sample++) {
                sampler.base = memory::live();
                sampler.timed = false;
                double sum = c.fn(sampler, n);

                if (!sampler.timed) {
                    std::fprintf(stderr, "%s never called time or repeat\n", id.c_str());
                    return 1;
                }

                // The first sample is a warm-up: it gives the checksum and picks k.
                if (sample == 0) {
                    checksum = sum;
                    if (sampler.took_ns < MIN_RUN_NS)
                        sampler.k = int(std::ceil(MIN_RUN_NS / std::max(sampler.took_ns, 1.0)));
                    continue;
                }

                ns_per_op.push_back(sampler.ns_per_op);
                timed_ns += sampler.took_ns;

                int count = int(ns_per_op.size());
                if (count >= MAX_SAMPLES) break;
                if (count >= MIN_SAMPLES && timed_ns >= MIN_TIMED_NS) break;
                if (count >= WALL_CAP_SAMPLES && now_ns() - wall_start >= WALL_CAP_NS) break;
            }

            double mid = median(ns_per_op);
            std::vector<double> deviations;
            for (double v : ns_per_op) deviations.push_back(std::abs(v - mid));

            std::printf("%s,%s,%s,%d,%.3f,%.3f,%.3f,%zu,%d,%zu,%zu,%.17g\n",
                        c.lib.empty() ? lib : c.lib.c_str(), c.group.c_str(), c.name.c_str(), n,
                        mid, *std::min_element(ns_per_op.begin(), ns_per_op.end()),
                        median(deviations), ns_per_op.size(), sampler.runs, sampler.live,
                        sampler.peak, checksum);
            std::fflush(stdout);

            std::fprintf(stderr, "  %-14s %-28s n=%-8d %10.2f ns/op\n",
                         c.lib.empty() ? lib : c.lib.c_str(), id.c_str(), n, mid);
        }
    }

    return 0;
}

} // namespace bench
