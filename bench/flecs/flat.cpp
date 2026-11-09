// Flat cases, see CASES.md. flecs 4.2 has no deferred mode on the world, so `.later` enqueues
// on stage 0 and merges it. Queries and systems are built in setup, since flecs expects them to
// be created once and kept. There is no direct storage walk, so `query.baseline` is left out.

#include "world.hpp"

namespace {

// >------------------------------------------------------------------ Lifecycle

template <typename... P>
double spawn_case(Sampler &s, int n) {
    World w;
    make_empty(w);

    s.time(n, [&] { spawn<P...>(w, n); });

    return sizeof...(P) == 0 ? count_alive(w) : sum_x<A>(w);
}

double kill(Sampler &s, int n) {
    World w;
    make_full(w, n);

    s.time(n, [&] {
        for (auto t : things) t.destruct();
    });

    return count_alive(w);
}

double kill_later(Sampler &s, int n) {
    World w;
    make_full(w, n);

    s.time(n, [&] {
        auto stage = w.get_stage(0);
        for (auto t : things) t.stage(stage).destruct();
        stage.merge();
    });

    return count_alive(w);
}

// >------------------------------------------------------------------ Structure

double add_tag(Sampler &s, int n) {
    World w;
    make_full(w, n);

    s.time(n, [&] {
        for (auto t : things) t.add<Tag>();
    });

    return double(w.count<Tag>());
}

double add_tag_later(Sampler &s, int n) {
    World w;
    make_full(w, n);

    s.time(n, [&] {
        auto stage = w.get_stage(0);
        for (auto t : things) t.stage(stage).add<Tag>();
        stage.merge();
    });

    return double(w.count<Tag>());
}

double remove_tag(Sampler &s, int n) {
    World w;
    make_full(w, n);
    for (auto t : things) t.add<Tag>();

    s.time(n, [&] {
        for (auto t : things) t.remove<Tag>();
    });

    return double(w.count<Tag>());
}

double add_d(Sampler &s, int n) {
    World w;
    make_empty(w);
    spawn<A, B, C>(w, n);

    s.time(n, [&] {
        for (auto t : things) t.set(D{});
    });

    return sum_x<D>(w);
}

double remove_d(Sampler &s, int n) {
    World w;
    make_full(w, n);

    s.time(n, [&] {
        for (auto t : things) t.remove<D>();
    });

    return double(w.count<D>());
}

// >-------------------------------------------------------------------- Queries

void update(A &a, const auto &...rest) { a.x += (1.0f + ... + rest.x); }

template <typename... Rest>
void run_query(flecs::query<A, const Rest...> &q) {
    q.each([](A &a, const Rest &...rest) { update(a, rest...); });
}

template <typename... Rest>
double uniform(Sampler &s, int n) {
    World w;
    make_full(w, n);
    auto q = w.query<A, const Rest...>();

    s.repeat(n, [&] { run_query(q); });

    return sum_x<A>(w);
}

double exclude(Sampler &s, int n) {
    World w;
    make_full(w, n);
    for (int i = 0; i < n; i += 2) things[i].add<Tag>();
    auto q = w.query_builder<A, const B>().without<Tag>().build();

    s.repeat(n, [&] { run_query(q); });

    return sum_x<A>(w);
}

template <int Permille>
double sparse(Sampler &s, int n) {
    World w;
    make_sparse(w, n, Permille);
    auto q = w.query<A, const B>();

    s.repeat(n, [&] { run_query(q); });

    return sum_x<A>(w);
}

template <typename... Rest>
double fragmented(Sampler &s, int n) {
    World w;
    make_fragmented(w, n);
    auto q = w.query<A, const Rest...>();

    s.repeat(n, [&] { run_query(q); });

    return sum_x<A>(w);
}

double system(Sampler &s, int n) {
    World w;
    make_full(w, n);
    auto sys = w.system<A, const B>().each([](A &a, const B &b) { update(a, b); });

    s.repeat(n, [&] { sys.run(); });

    return sum_x<A>(w);
}

// >--------------------------------------------------------------------- Access

// The j-th entity in spawn order, or in shuffled order. rand is a compile-time constant at
// every call, so the branch folds away.
flecs::entity handle(bool rand, int j) { return rand ? things[perm[j]] : things[j]; }

template <bool Rand>
double get_1(Sampler &s, int n) {
    World w;
    make_full(w, n);

    double sum = 0;
    s.repeat(n, [&] {
        for (int j = 0; j < n; j++) sum += handle(Rand, j).try_get<A>()->x;
    });

    return sum;
}

template <bool Rand>
double get_4(Sampler &s, int n) {
    World w;
    make_full(w, n);

    double sum = 0;
    s.repeat(n, [&] {
        for (int j = 0; j < n; j++) {
            handle(Rand, j).get([&](const A &a, const B &b, const C &c, const D &d) {
                sum += a.x + b.x + c.x + d.x;
            });
        }
    });

    return sum;
}

template <bool Rand>
double write_1(Sampler &s, int n) {
    World w;
    make_full(w, n);

    s.repeat(n, [&] {
        for (int j = 0; j < n; j++) handle(Rand, j).get_mut<A>().x += 1;
    });

    return sum_x<A>(w);
}

template <bool Rand>
double has(Sampler &s, int n) {
    World w;
    make_sparse(w, n, 500);

    double count = 0;
    s.repeat(n, [&] {
        for (int j = 0; j < n; j++) count += handle(Rand, j).has<B>();
    });

    return count;
}

template <bool Rand>
double alive(Sampler &s, int n) {
    World w;
    make_full(w, n);
    for (int i = 0; i < n; i += 2) things[i].destruct();

    double count = 0;
    s.repeat(n, [&] {
        for (int j = 0; j < n; j++) count += handle(Rand, j).is_alive();
    });

    return count;
}

// >---------------------------------------------------------------------- Churn

constexpr int FRAMES = 100;

void churn_frame(World &w, flecs::query<A, const B> &q, int n, int frame) {
    int per = n / FRAMES;
    int first = frame * per;

    for (int j = first; j < first + per; j++) things[perm[j]].destruct();

    for (int j = first; j < first + per; j++)
        things[perm[j]] = w.entity().set(A{}).set(B{}).set(C{}).set(D{});

    run_query(q);
}

double churn_frames(Sampler &s, int n) {
    World w;
    make_full(w, n);
    auto q = w.query<A, const B>();

    s.time(FRAMES, [&] {
        for (int frame = 0; frame < FRAMES; frame++) churn_frame(w, q, n, frame);
    });

    return sum_x<A>(w);
}

double churn_after(Sampler &s, int n) {
    World w;
    make_full(w, n);
    auto q = w.query<A, const B>();
    for (int frame = 0; frame < FRAMES; frame++) churn_frame(w, q, n, frame);

    s.repeat(n, [&] { run_query(q); });

    return sum_x<A>(w);
}

} // namespace

std::vector<Case> flat_cases() {
    return {
        {"lifecycle", "spawn.0", spawn_case<>},
        {"lifecycle", "spawn.1", spawn_case<A>},
        {"lifecycle", "spawn.2", spawn_case<A, B>},
        {"lifecycle", "spawn.3", spawn_case<A, B, C>},
        {"lifecycle", "spawn.4", spawn_case<A, B, C, D>},
        {"lifecycle", "kill", kill},
        {"lifecycle", "kill.later", kill_later},

        {"structure", "add.tag", add_tag},
        {"structure", "add.tag.later", add_tag_later},
        {"structure", "remove.tag", remove_tag},
        {"structure", "add.D", add_d},
        {"structure", "remove.D", remove_d},

        {"query", "uniform.1", uniform<>},
        {"query", "uniform.2", uniform<B>},
        {"query", "uniform.3", uniform<B, C>},
        {"query", "uniform.4", uniform<B, C, D>},
        {"query", "exclude", exclude},
        {"query", "sparse.10", sparse<10>},
        {"query", "sparse.100", sparse<100>},
        {"query", "sparse.500", sparse<500>},
        {"query", "fragmented.1", fragmented<>},
        {"query", "fragmented.2", fragmented<B>},
        {"query", "system", system},

        {"access", "get.1.seq", get_1<false>},
        {"access", "get.1.rand", get_1<true>},
        {"access", "get.4.seq", get_4<false>},
        {"access", "get.4.rand", get_4<true>},
        {"access", "write.1.seq", write_1<false>},
        {"access", "write.1.rand", write_1<true>},
        {"access", "has.seq", has<false>},
        {"access", "has.rand", has<true>},
        {"access", "alive.seq", alive<false>},
        {"access", "alive.rand", alive<true>},

        {"churn", "frames", churn_frames},
        {"churn", "after", churn_after},
    };
}
