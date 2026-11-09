// EnTT implementation of CASES.md. Run with: just entt

#include "world.hpp"

int main(int argc, char **argv) {
    auto cases = flat_cases();
    for (auto &c : hierarchy_cases()) cases.push_back(c);

    return bench::run("entt", cases, argc, argv);
}
