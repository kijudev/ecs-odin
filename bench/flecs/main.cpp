// flecs implementation of CASES.md. Run with: just flecs

#include "memory.hpp"
#include "world.hpp"

// flecs allocates through its os api rather than operator new, so point it at the counters.
static void count_flecs_allocations() {
    ecs_os_set_api_defaults();

    ecs_os_api_t api = ecs_os_api;
    api.malloc_ = [](ecs_size_t size) { return memory::alloc(size_t(size)); };
    api.calloc_ = [](ecs_size_t size) { return memory::alloc_zeroed(1, size_t(size)); };
    api.realloc_ = [](void *ptr, ecs_size_t size) { return memory::resize(ptr, size_t(size)); };
    api.free_ = [](void *ptr) { memory::free(ptr); };

    ecs_os_set_api(&api);
}

int main(int argc, char **argv) {
    count_flecs_allocations();

    auto cases = flat_cases();
    for (auto &c : hierarchy_cases()) cases.push_back(c);

    return bench::run("flecs", cases, argc, argv);
}
