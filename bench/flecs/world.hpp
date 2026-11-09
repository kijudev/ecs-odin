// flecs setups shared by the flat and hierarchy cases.
#pragma once

#include <flecs.h>
#include <vector>

#include "data.hpp"
#include "harness.hpp"

using namespace bench;

using World = flecs::world;

// things[i] is the i-th spawned entity.
inline std::vector<flecs::entity> things;

std::vector<Case> flat_cases();
std::vector<Case> hierarchy_cases();

// >---------------------------------------------------------------------- Setup

inline void make_empty(World &w) {
    w.component<A>();
    w.component<B>();
    w.component<C>();
    w.component<D>();
    w.component<Tag>();
    w.component<Local>();
    w.component<Global>();
}

template <typename... P>
void spawn(World &w, int n) {
    things.resize(n);
    for (auto &t : things) {
        t = w.entity();
        (t.set(P{}), ...);
    }
}

inline void make_full(World &w, int n) {
    make_empty(w);
    spawn<A, B, C, D>(w, n);
}

inline void make_sparse(World &w, int n, int permille) {
    make_empty(w);
    spawn<A>(w, n);
    for (int i = 0; i < n; i++)
        if (is_sparse(i, permille)) things[i].set(B{});
}

inline void make_fragmented(World &w, int n) {
    make_empty(w);
    spawn<>(w, n);
    for (int i = 0; i < n; i++) {
        int bits = i % 16;
        if (bits & 1) things[i].set(A{});
        if (bits & 2) things[i].set(B{});
        if (bits & 4) things[i].set(C{});
        if (bits & 8) things[i].set(D{});
        if (bits == 0) things[i].add<Tag>();
    }
}

// >------------------------------------------------------------------ Checksums

template <typename P>
double sum_x(World &w) {
    double sum = 0;
    w.each([&](const P &part) { sum += part.x; });
    return sum;
}

inline double count_alive(World &) {
    double alive = 0;
    for (auto t : things) alive += t.is_alive();
    return alive;
}
