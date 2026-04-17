#include <limits.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
    char exe_path[PATH_MAX];
    uint32_t exe_path_size = sizeof(exe_path);

    if (_NSGetExecutablePath(exe_path, &exe_path_size) != 0) {
        fprintf(stderr, "failed to resolve executable path\n");
        return 1;
    }

    char *last_slash = strrchr(exe_path, '/');
    if (!last_slash) {
        fprintf(stderr, "unexpected executable path: %s\n", exe_path);
        return 1;
    }
    *last_slash = '\0';

    if (chdir(exe_path) != 0) {
        perror("chdir");
        return 1;
    }

    const char *old_path = getenv("PATH");
    const char *suffix = old_path ? old_path : "";
    size_t path_len = strlen("./bin:") + strlen(suffix) + 1;
    char *new_path = malloc(path_len);
    if (!new_path) {
        fprintf(stderr, "failed to allocate PATH buffer\n");
        return 1;
    }

    snprintf(new_path, path_len, "./bin:%s", suffix);
    if (setenv("PATH", new_path, 1) != 0) {
        perror("setenv");
        free(new_path);
        return 1;
    }
    free(new_path);

    char **child_argv = calloc((size_t)argc + 1, sizeof(char *));
    if (!child_argv) {
        fprintf(stderr, "failed to allocate argv\n");
        return 1;
    }

    child_argv[0] = "./bin/gephgui-wry";
    for (int i = 1; i < argc; ++i) {
        child_argv[i] = argv[i];
    }
    child_argv[argc] = NULL;

    execv("./bin/gephgui-wry", child_argv);
    perror("execv");
    free(child_argv);
    return 1;
}
