// Flat cases, see CASES.md. EnTT has no command buffer and no systems, so
// `.later` and `query.system` are left out.

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
        for (auto t : things) w.destroy(t);
    });

    return count_alive(w);
}

// >------------------------------------------------------------------ Structure

double add_tag(Sampler &s, int n) {
    World w;
    make_full(w, n);

    s.time(n, [&] {
        for (auto t : things) w.emplace<Tag>(t);
    });

    return double(w.storage<Tag>().size());
}

double remove_tag(Sampler &s, int n) {
    World w;
    make_full(w, n);
    for (auto t : things) w.emplace<Tag>(t);

    s.time(n, [&] {
        for (auto t : things) w.remove<Tag>(t);
    });

    return double(w.storage<Tag>().size());
}

double add_d(Sampler &s, int n) {
    World w;
    make_empty(w);
    spawn<A, B, C>(w, n);

    s.time(n, [&] {
        for (auto t : things) w.emplace<D>(t);
    });

    return sum_x<D>(w);
}

double remove_d(Sampler &s, int n) {
    World w;
    make_full(w, n);

    s.time(n, [&] {
        for (auto t : things) w.remove<D>(t);
    });

    return double(w.storage<D>().size());
}

// >-------------------------------------------------------------------- Queries

void update(A &a, const auto &...rest) { a.x += (1.0f + ... + rest.x); }

template <typename... Rest>
void query(World &w, auto... exclude) {
    w.view<A, const Rest...>(exclude...).each([](A &a, const Rest &...rest) {
        update(a, rest...);
    });
}

template <typename... Rest>
double uniform(Sampler &s, int n) {
    World w;
    make_full(w, n);

    s.repeat(n, [&] { query<Rest...>(w); });

    return sum_x<A>(w);
}

double exclude(Sampler &s, int n) {
    World w;
    make_full(w, n);
    for (int i = 0; i < n; i += 2) w.emplace<Tag>(things[i]);

    s.repeat(n, [&] { query<B>(w, entt::exclude<Tag>); });

    return sum_x<A>(w);
}

template <int Permille>
double sparse(Sampler &s, int n) {
    World w;
    make_sparse(w, n, Permille);

    s.repeat(n, [&] { query<B>(w); });

    return sum_x<A>(w);
}

template <typename... Rest>
double fragmented(Sampler &s, int n) {
    World w;
    make_fragmented(w, n);

    s.repeat(n, [&] { query<Rest...>(w); });

    return sum_x<A>(w);
}

double baseline(Sampler &s, int n) {
    World w;
    make_full(w, n);

    s.repeat(n, [&] {
        for (auto &a : w.storage<A>()) a.x += 1;
    });

    return sum_x<A>(w);
}

// >--------------------------------------------------------------------- Access

// The j-th entity in spawn order, or in shuffled order. rand is a compile-time
// constant at every call, so the branch folds away.
entity handle(bool rand, int j) { return rand ? things[perm[j]] : things[j]; }

template <bool Rand>
double get_1(Sampler &s, int n) {
    World w;
    make_full(w, n);

    double sum = 0;
    s.repeat(n, [&] {
        for (int j = 0; j < n; j++) sum += w.try_get<A>(handle(Rand, j))->x;
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
            auto [a, b, c, d] = w.try_get<A, B, C, D>(handle(Rand, j));
            sum += a->x + b->x + c->x + d->x;
        }
    });

    return sum;
}

template <bool Rand>
double write_1(Sampler &s, int n) {
    World w;
    make_full(w, n);

    s.repeat(n, [&] {
        for (int j = 0; j < n; j++) w.get<A>(handle(Rand, j)).x += 1;
    });

    return sum_x<A>(w);
}

template <bool Rand>
double has(Sampler &s, int n) {
    World w;
    make_sparse(w, n, 500);

    double count = 0;
    s.repeat(n, [&] {
        for (int j = 0; j < n; j++) count += w.all_of<B>(handle(Rand, j));
    });

    return count;
}

template <bool Rand>
double alive(Sampler &s, int n) {
    World w;
    make_full(w, n);
    for (int i = 0; i < n; i += 2) w.destroy(things[i]);

    double count = 0;
    s.repeat(n, [&] {
        for (int j = 0; j < n; j++) count += w.valid(handle(Rand, j));
    });

    return count;
}

// >---------------------------------------------------------------------- Churn

constexpr int FRAMES = 100;

void churn_frame(World &w, int n, int frame) {
    int per = n / FRAMES;
    int first = frame * per;

    for (int j = first; j < first + per; j++) w.destroy(things[perm[j]]);

    for (int j = first; j < first + per; j++) {
        auto t = w.create();
        w.emplace<A>(t);
        w.emplace<B>(t);
        w.emplace<C>(t);
        w.emplace<D>(t);
        things[perm[j]] = t;
    }

    query<B>(w);
}

double churn_frames(Sampler &s, int n) {
    World w;
    make_full(w, n);

    s.time(FRAMES, [&] {
        for (int frame = 0; frame < FRAMES; frame++) churn_frame(w, n, frame);
    });

    return sum_x<A>(w);
}

double churn_after(Sampler &s, int n) {
    World w;
    make_full(w, n);
    for (int frame = 0; frame < FRAMES; frame++) churn_frame(w, n, frame);

    s.repeat(n, [&] { query<B>(w); });

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

        {"structure", "add.tag", add_tag},
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
        {"query", "baseline", baseline},

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
