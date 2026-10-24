#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc != 3) return 2;
    const char *mode = argv[1];
    alarm(15); // A failing test must not leave a fixture running indefinitely.
    if (!strcmp(mode, "stubborn") || !strcmp(mode, "match") || !strcmp(mode, "closed-output")) {
        signal(SIGTERM, SIG_IGN);
    }
    FILE *pid = fopen(argv[2], "w");
    if (!pid) return 3;
    fprintf(pid, "%d", getpid());
    fclose(pid);

    if (!strcmp(mode, "stubborn")) {
        for (;;) pause();
    } else if (!strcmp(mode, "closed-output")) {
        close(STDOUT_FILENO);
        for (;;) pause();
    } else if (!strcmp(mode, "match")) {
        // Split a Korean UTF-8 character across two writes, after an unrelated notification.
        const char first[] = "{\"notice\":true}\n{\"id\":1,\"text\":\"\xea";
        write(STDOUT_FILENO, first, sizeof(first) - 1);
        usleep(30000);
        const char last[] = "\xb0\x80\"}\n";
        write(STDOUT_FILENO, last, sizeof(last) - 1);
        for (;;) pause();
    } else if (!strcmp(mode, "flood")) {
        char block[8192];
        memset(block, 'x', sizeof(block));
        for (;;) {
            if (write(STDOUT_FILENO, block, sizeof(block)) < 0) return 0;
        }
    } else if (!strcmp(mode, "echo")) {
        char block[4096];
        ssize_t count;
        while ((count = read(STDIN_FILENO, block, sizeof(block))) > 0) {
            ssize_t sent = 0;
            while (sent < count) {
                ssize_t wrote = write(STDOUT_FILENO, block + sent, count - sent);
                if (wrote < 0) return 4;
                sent += wrote;
            }
            if (memchr(block, '\n', count)) break;
        }
    } else if (!strcmp(mode, "tail")) {
        const char text[] = "{\"id\":1}";
        write(STDOUT_FILENO, text, sizeof(text) - 1);
    } else {
        const char text[] = "usage: 정상\n";
        write(STDOUT_FILENO, text, sizeof(text) - 1);
    }
    return 0;
}
