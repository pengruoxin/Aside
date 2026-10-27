#ifndef ASIDE_RIME_BRIDGE_H
#define ASIDE_RIME_BRIDGE_H
#include <stdint.h>
#include <stddef.h>
typedef struct {
    char *preedit;
    int cursor;
    int highlighted;
    size_t count;
    char **candidates;
} AsideRimeContext;
int aside_rime_initialize(const char *data, const char *user, const char *prebuilt);
void aside_rime_finalize(void);
uintptr_t aside_rime_create(void);
void aside_rime_destroy(uintptr_t session);
int aside_rime_process(uintptr_t session, int key, int modifiers);
int aside_rime_select(uintptr_t session, size_t index);
void aside_rime_commit(uintptr_t session);
void aside_rime_clear(uintptr_t session);
char *aside_rime_take_commit(uintptr_t session);
int aside_rime_context(uintptr_t session, AsideRimeContext *context);
void aside_rime_free_context(AsideRimeContext *context);
void aside_rime_free_string(char *string);
#endif
