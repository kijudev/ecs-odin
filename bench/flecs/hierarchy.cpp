// Hierarchy cases, see CASES.md. Every case runs twice: with the ChildOf pair (one table per
// parent, reported as `flecs`) and with the non-fragmenting Parent component (`flecs-parent`).
// flecs keeps its own parent-first order, so there is no `rebuild` case.

#include <string>

#include "world.hpp"

namespace {

// >-------------------------------------------------------------------- Helpers

template <bool P>
void attach(flecs::entity child, flecs::entity parent) {
    if constexpr (P) {
        child.set(flecs::Parent{parent});
    } else {
        child.child_of(parent);
    }
}

void propagate_one(const Local &local, Global &global, const Global *parent) {
    global = parent ? Global{parent->x + local.x, parent->y + local.y} : Global{local.x, local.y};
}

// Propagation over ChildOf: one cascade query visits parents before their children.
struct ChildOfPropagate {
    flecs::query<const Local, Global, const Global *> q;

    explicit ChildOfPropagate(World &w)
        : q(w.query_builder<const Local, Global, const Global *>().term_at(2).cascade().build()) {}

    void run() { q.each(propagate_one); }
};

// Propagation over Parent: the roots first, then the children one depth group at a time.
// Groups are not iterated in depth order on their own, hence the explicit loop.
struct ParentPropagate {
    World &w;
    flecs::query<const Local, Global> roots;
    flecs::query<const Local, Global, const flecs::Parent> children;

    explicit ParentPropagate(World &w)
        : w(w), roots(w.query_builder<const Local, Global>().without<flecs::Parent>().build()),
          children(w.query_builder<const Local, Global, const flecs::Parent>()
                       .group_by(flecs::ParentDepth)
                       .build()) {}

    void run() {
        roots.each(
            [](const Local &local, Global &global) { propagate_one(local, global, nullptr); });

        for (uint64_t depth = 1; children.group_info(depth); depth++) {
            children.set_group(depth).each(
                [&](const Local &local, Global &global, const flecs::Parent &parent) {
                    propagate_one(local, global, flecs::entity(w, parent.value).try_get<Global>());
                });
        }
    }
};

template <bool P>
using Propagate = std::conditional_t<P, ParentPropagate, ChildOfPropagate>;

// >---------------------------------------------------------------------- Setup

void make_nodes(World &w, int n) {
    make_empty(w);
    spawn<Local, Global>(w, n);
}

template <bool P>
void attach_all(Shape shape, int n) {
    for (int i = 0; i < n; i++)
        if (int p = parent_of(shape, i); p >= 0) attach<P>(things[i], things[p]);
}

template <bool P>
void make_shape(World &w, Shape shape, int n) {
    make_nodes(w, n);
    attach_all<P>(shape, n);
}

double global_sum(World &w) {
    double sum = 0;
    w.each([&](const Global &g) { sum += g.x + g.y; });
    return sum;
}

double count_children() {
    double count = 0;
    for (auto t : things)
        if (t.is_alive()) count += t.parent() != 0;
    return count;
}

// >---------------------------------------------------------------------- Cases

template <Shape S, bool P>
double attach_case(Sampler &s, int n) {
    World w;
    make_nodes(w, n);

    s.time(n - count_roots(S, n), [&] { attach_all<P>(S, n); });

    return count_children();
}

template <Shape S, bool P>
double attach_later_case(Sampler &s, int n) {
    World w;
    make_nodes(w, n);

    s.time(n - count_roots(S, n), [&] {
        auto stage = w.get_stage(0);
        for (int i = 0; i < n; i++)
            if (int p = parent_of(S, i); p >= 0) attach<P>(things[i].stage(stage), things[p]);
        stage.merge();
    });

    return count_children();
}

template <Shape S, bool P>
double propagate_case(Sampler &s, int n) {
    World w;
    make_shape<P>(w, S, n);
    Propagate<P> propagate(w);

    s.repeat(n, [&] { propagate.run(); });

    return global_sum(w);
}

template <Shape S, bool P, bool Rand>
double parent_case(Sampler &s, int n) {
    World w;
    make_shape<P>(w, S, n);

    double count = 0;
    s.repeat(n, [&] {
        for (int j = 0; j < n; j++) count += things[Rand ? perm[j] : j].parent() != 0;
    });

    return count;
}

template <Shape S, bool P>
double children_case(Sampler &s, int n) {
    World w;
    make_shape<P>(w, S, n);

    double count = 0;
    s.repeat(n, [&] {
        for (auto t : things) t.children([&](flecs::entity) { count += 1; });
    });

    return count;
}

template <Shape S, bool P>
double reparent_case(Sampler &s, int n) {
    World w;
    make_shape<P>(w, S, n);
    Propagate<P> propagate(w);
    propagate.run(); // As in a running game, so every Global starts fresh.

    s.time(n / 10, [&] {
        for (int j = 0; j < n / 10; j++)
            if (int c = perm[j]; c > 0) attach<P>(things[c], things[reparent_target(S, c)]);
    });

    propagate.run();
    return global_sum(w);
}

template <Shape S, bool P>
double kill_whole_case(Sampler &s, int n) {
    World w;
    make_shape<P>(w, S, n);

    s.time(n, [&] {
        for (int i = 0; i < n; i++)
            if (parent_of(S, i) < 0) things[i].destruct();
    });

    return count_alive(w);
}

template <Shape S, bool P>
double kill_small_case(Sampler &s, int n) {
    World w;
    make_shape<P>(w, S, n);

    s.time(n / 100, [&] {
        for (int j = 0; j < n / 100; j++)
            if (things[perm[j]].is_alive()) things[perm[j]].destruct();
    });

    return count_alive(w);
}

template <Shape S, bool P>
void add_shape(std::vector<Case> &cases, const std::string &shape) {
    std::string lib = P ? "flecs-parent" : "";
    cases.push_back({"hierarchy", "attach." + shape, attach_case<S, P>, lib});
    cases.push_back({"hierarchy", "attach.later." + shape, attach_later_case<S, P>, lib});
    cases.push_back({"hierarchy", "propagate." + shape, propagate_case<S, P>, lib});
    cases.push_back({"hierarchy", "parent.seq." + shape, parent_case<S, P, false>, lib});
    cases.push_back({"hierarchy", "parent.rand." + shape, parent_case<S, P, true>, lib});
    cases.push_back({"hierarchy", "children." + shape, children_case<S, P>, lib});
    cases.push_back({"hierarchy", "reparent." + shape, reparent_case<S, P>, lib});
    cases.push_back({"hierarchy", "kill.whole." + shape, kill_whole_case<S, P>, lib});
    cases.push_back({"hierarchy", "kill.small." + shape, kill_small_case<S, P>, lib});
}

template <bool P>
void add_shapes(std::vector<Case> &cases) {
    add_shape<Shape::Tree, P>(cases, "tree");
    add_shape<Shape::Forest, P>(cases, "forest");
    add_shape<Shape::Chain, P>(cases, "chain");
}

} // namespace

std::vector<Case> hierarchy_cases() {
    std::vector<Case> cases;
    add_shapes<false>(cases);
    add_shapes<true>(cases);
    return cases;
}
