// Parts, shuffles and hierarchy shapes shared by every case. oecs/data.odin mirrors this
// exactly, so the checksums of all libraries can be compared.
#pragma once

#include <cstdint>
#include <numeric>
#include <utility>
#include <vector>

namespace bench {

// >---------------------------------------------------------------------- Parts

// A, B, C and D share a shape but must be distinct types for EnTT and flecs.
template <int I>
struct Part {
    float x = 1, y = 0, z = 0, w = 0;
};

using A = Part<0>;
using B = Part<1>;
using C = Part<2>;
using D = Part<3>;

struct Tag {};

struct Local {
    float x = 1, y = 1;
};

struct Global {
    float x = 0, y = 0;
};

// >------------------------------------------------------------------ Shuffling

// splitmix64 finalizer.
inline uint64_t hash(uint64_t i) {
    i += 0x9E3779B97F4A7C15ull;
    i = (i ^ (i >> 30)) * 0xBF58476D1CE4E5B9ull;
    i = (i ^ (i >> 27)) * 0x94D049BB133111EBull;
    return i ^ (i >> 31);
}

// 0 .. n-1, shuffled. Filled by the harness before the cases of each size run.
inline std::vector<int> perm;

inline void make_perm(int n) {
    perm.resize(n);
    std::iota(perm.begin(), perm.end(), 0);
    for (int i = n - 1; i > 0; i--) std::swap(perm[i], perm[hash(uint64_t(n) + i) % (i + 1)]);
}

// Whether entity i is in the `permille` part of a sparse setup.
inline bool is_sparse(int i, int permille) { return hash(i) % 1000 < uint64_t(permille); }

// >---------------------------------------------------------- Hierarchy shapes

enum class Shape { Tree, Forest, Chain };

// The parent index of entity i, or -1 for a root. Always lower than i.
inline int parent_of(Shape shape, int i) {
    switch (shape) {
    case Shape::Tree:
        return i == 0 ? -1 : (i - 1) / 4;
    case Shape::Forest: {
        int r = i % 7, root = i - r;
        if (r == 0) return -1;
        return r <= 2 ? root : root + 1 + (r - 3) / 2;
    }
    case Shape::Chain:
        return i % 64 == 0 ? -1 : i - 1;
    }
    return -1;
}

inline int count_roots(Shape shape, int n) {
    int roots = 0;
    for (int i = 0; i < n; i++) roots += parent_of(shape, i) < 0;
    return roots;
}

// The new parent of a reparented entity c: a random root of the original shape below c. Lower
// than c, so never one of its descendants, and shallow, so depths stay far below flecs' limit
// of 128.
inline int reparent_target(Shape shape, int c) {
    int stride = shape == Shape::Tree ? c : shape == Shape::Forest ? 7 : 64;
    return stride * int(hash(c) % uint64_t((c - 1) / stride + 1));
}

} // namespace bench
