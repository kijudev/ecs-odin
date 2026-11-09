// Hierarchy cases, see CASES.md. EnTT has no hierarchy, so this is the usual intrusive Rel
// component: a parent and a singly linked list of children. `rebuild` sorts the storages by
// depth so propagation can run parents first.

#include <string>

#include "world.hpp"

namespace {

struct Rel {
    entity parent = entt::null;
    entity first_child = entt::null;
    entity next_sibling = entt::null;
    int depth = 0;
};

// >-------------------------------------------------------------------- Helpers

void unlink(World &w, entity child, Rel &rel) {
    auto *link = &w.get<Rel>(rel.parent).first_child;
    while (*link != child) link = &w.get<Rel>(*link).next_sibling;
    *link = rel.next_sibling;
    rel.parent = entt::null;
}

void attach(World &w, entity child, entity parent) {
    auto &rel = w.get<Rel>(child);
    if (rel.parent != entt::null) unlink(w, child, rel);

    auto &parent_rel = w.get<Rel>(parent);
    rel.parent = parent;
    rel.next_sibling = parent_rel.first_child;
    parent_rel.first_child = child;
}

void rebuild(World &w) {
    for (auto [e, rel] : w.view<Rel>().each()) {
        rel.depth = 0;
        for (auto p = rel.parent; p != entt::null; p = w.get<Rel>(p).parent) rel.depth++;
    }

    w.sort<Rel>([](const Rel &a, const Rel &b) { return a.depth < b.depth; });
    w.sort<Local, Rel>();
    w.sort<Global, Rel>();
}

void propagate(World &w) {
    auto view = w.view<const Rel, const Local, Global>();
    view.use<Rel>();

    view.each([&](const Rel &rel, const Local &local, Global &global) {
        if (rel.parent == entt::null) {
            global = {local.x, local.y};
        } else {
            auto &parent = w.get<Global>(rel.parent);
            global = {parent.x + local.x, parent.y + local.y};
        }
    });
}

void kill_tree(World &w, entity root) {
    auto &rel = w.get<Rel>(root);
    if (rel.parent != entt::null) unlink(w, root, rel);

    std::vector<entity> stack = {root};
    while (!stack.empty()) {
        auto e = stack.back();
        stack.pop_back();

        for (auto c = w.get<Rel>(e).first_child; c != entt::null; c = w.get<Rel>(c).next_sibling)
            stack.push_back(c);

        w.destroy(e);
    }
}

// >---------------------------------------------------------------------- Setup

void make_nodes(World &w, int n) {
    make_empty(w);
    spawn<Local, Global, Rel>(w, n);
}

void attach_all(World &w, Shape shape, int n) {
    for (int i = 0; i < n; i++)
        if (int p = parent_of(shape, i); p >= 0) attach(w, things[i], things[p]);
}

void make_shape(World &w, Shape shape, int n) {
    make_nodes(w, n);
    attach_all(w, shape, n);
    rebuild(w);
}

double global_sum(World &w) {
    double sum = 0;
    for (auto &g : w.storage<Global>()) sum += g.x + g.y;
    return sum;
}

double count_children(World &w) {
    double count = 0;
    for (auto t : things)
        if (w.valid(t)) count += w.get<Rel>(t).parent != entt::null;
    return count;
}

// >---------------------------------------------------------------------- Cases

template <Shape S>
double attach_case(Sampler &s, int n) {
    World w;
    make_nodes(w, n);

    s.time(n - count_roots(S, n), [&] { attach_all(w, S, n); });

    return count_children(w);
}

template <Shape S>
double rebuild_case(Sampler &s, int n) {
    World w;
    make_nodes(w, n);
    attach_all(w, S, n);

    s.time(n, [&] { rebuild(w); });

    return 0;
}

template <Shape S>
double propagate_case(Sampler &s, int n) {
    World w;
    make_shape(w, S, n);

    s.repeat(n, [&] { propagate(w); });

    return global_sum(w);
}

template <Shape S, bool Rand>
double parent_case(Sampler &s, int n) {
    World w;
    make_shape(w, S, n);

    double count = 0;
    s.repeat(n, [&] {
        for (int j = 0; j < n; j++)
            count += w.get<Rel>(things[Rand ? perm[j] : j]).parent != entt::null;
    });

    return count;
}

template <Shape S>
double children_case(Sampler &s, int n) {
    World w;
    make_shape(w, S, n);

    double count = 0;
    s.repeat(n, [&] {
        for (auto t : things)
            for (auto c = w.get<Rel>(t).first_child; c != entt::null;
                 c = w.get<Rel>(c).next_sibling)
                count += 1;
    });

    return count;
}

template <Shape S>
double reparent_case(Sampler &s, int n) {
    World w;
    make_shape(w, S, n);
    propagate(w); // As in a running game, so every Global starts fresh.

    s.time(n / 10, [&] {
        for (int j = 0; j < n / 10; j++)
            if (int c = perm[j]; c > 0) attach(w, things[c], things[reparent_target(S, c)]);
    });

    rebuild(w);
    propagate(w);
    return global_sum(w);
}

template <Shape S>
double kill_whole_case(Sampler &s, int n) {
    World w;
    make_shape(w, S, n);

    s.time(n, [&] {
        for (int i = 0; i < n; i++)
            if (parent_of(S, i) < 0) kill_tree(w, things[i]);
    });

    return count_alive(w);
}

template <Shape S>
double kill_small_case(Sampler &s, int n) {
    World w;
    make_shape(w, S, n);

    s.time(n / 100, [&] {
        for (int j = 0; j < n / 100; j++)
            if (w.valid(things[perm[j]])) kill_tree(w, things[perm[j]]);
    });

    return count_alive(w);
}

template <Shape S>
void add_shape(std::vector<Case> &cases, const std::string &shape) {
    cases.push_back({"hierarchy", "attach." + shape, attach_case<S>});
    cases.push_back({"hierarchy", "rebuild." + shape, rebuild_case<S>});
    cases.push_back({"hierarchy", "propagate." + shape, propagate_case<S>});
    cases.push_back({"hierarchy", "parent.seq." + shape, parent_case<S, false>});
    cases.push_back({"hierarchy", "parent.rand." + shape, parent_case<S, true>});
    cases.push_back({"hierarchy", "children." + shape, children_case<S>});
    cases.push_back({"hierarchy", "reparent." + shape, reparent_case<S>});
    cases.push_back({"hierarchy", "kill.whole." + shape, kill_whole_case<S>});
    cases.push_back({"hierarchy", "kill.small." + shape, kill_small_case<S>});
}

} // namespace

std::vector<Case> hierarchy_cases() {
    std::vector<Case> cases;
    add_shape<Shape::Tree>(cases, "tree");
    add_shape<Shape::Forest>(cases, "forest");
    add_shape<Shape::Chain>(cases, "chain");
    return cases;
}
