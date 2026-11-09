// EnTT setups shared by the flat and hierarchy cases.
#pragma once

#include <entt/entt.hpp>
#include <vector>

#include "data.hpp"
#include "harness.hpp"

using namespace bench;

using World = entt::registry;
using entt::entity;

// things[i] is the i-th spawned entity.
inline std::vector<entity> things;

std::vector<Case> flat_cases();
std::vector<Case> hierarchy_cases();

// >---------------------------------------------------------------------- Setup

inline void make_empty(World &w) {
    w.storage<A>();
    w.storage<B>();
    w.storage<C>();
    w.storage<D>();
    w.storage<Tag>();
    w.storage<Local>();
    w.storage<Global>();
}

template <typename... P>
void spawn(World &w, int n) {
    things.resize(n);
    for (auto &t : things) {
        t = w.create();
        (w.emplace<P>(t), ...);
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
        if (is_sparse(i, permille)) w.emplace<B>(things[i]);
}

inline void make_fragmented(World &w, int n) {
    make_empty(w);
    spawn<>(w, n);
    for (int i = 0; i < n; i++) {
        int bits = i % 16;
        if (bits & 1) w.emplace<A>(things[i]);
        if (bits & 2) w.emplace<B>(things[i]);
        if (bits & 4) w.emplace<C>(things[i]);
        if (bits & 8) w.emplace<D>(things[i]);
        if (bits == 0) w.emplace<Tag>(things[i]);
    }
}

// >------------------------------------------------------------------ Checksums

template <typename P>
double sum_x(World &w) {
    double sum = 0;
    for (auto &part : w.storage<P>()) sum += part.x;
    return sum;
}

inline double count_alive(World &w) {
    double alive = 0;
    for (auto t : things) alive += w.valid(t);
    return alive;
}
