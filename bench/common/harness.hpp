// The sampling harness, see "Method" in CASES.md. oecs/harness.odin follows the same rules.
#pragma once

#include <cstdint>
#include <span>
#include <string>

namespace bench {

class Sampler;

// Runs one sample: builds a world (untimed), wraps the measured part in Sampler::time or
// Sampler::repeat, and returns a checksum of the world afterwards.
using CaseFn = double (*)(Sampler &, int n);

struct Case {
    std::string group;
    std::string name;
    CaseFn fn;
    std::string lib = {}; // Overrides the binary's library name, for variants like flecs-parent.
};

class Sampler {
  public:
    // Times fn once. ops is how many operations fn does, for ns/op.
    template <typename F>
    void time(int64_t ops, F &&fn) {
        begin();
        fn();
        end(ops, 1);
    }

    // Times fn k times in a row on the same world, with k picked by the harness so tiny runs
    // stay measurable. Only for operations that can run again on their own result.
    template <typename F>
    void repeat(int64_t ops, F &&fn) {
        begin();
        for (int i = 0; i < k; i++) fn();
        end(ops, k);
    }

  private:
    friend int run(const char *, std::span<const Case>, int, char **);

    void begin();
    void end(int64_t ops, int runs);

    int k = 1;    // Runs per repeat sample, picked from the warm-up.
    int runs = 1; // Runs in the last sample: 1 for time, k for repeat.
    bool timed = false;
    std::size_t base = 0, live = 0, peak = 0;
    double start_ns = 0, took_ns = 0, ns_per_op = 0;
};

// Parses `--n 10000,100000` and `--case 'query.*'`, runs the matching cases and prints CSV.
int run(const char *lib, std::span<const Case> cases, int argc, char **argv);

} // namespace bench
