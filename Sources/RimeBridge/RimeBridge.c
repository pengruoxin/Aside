#include "RimeBridge.h"
#include <rime_api.h>
#include <stdlib.h>
#include <string.h>

static RimeApi *api = NULL;
static char *data_path, *user_path, *prebuilt_path;

int aside_rime_initialize(const char *data, const char *user, const char *prebuilt) {
    if (api) return 1;
    api = rime_get_api();
    if (!api) return 0;
    data_path = strdup(data);
    user_path = strdup(user);
    prebuilt_path = strdup(prebuilt);
    RIME_STRUCT(RimeTraits, traits);
    traits.shared_data_dir = data_path;
    traits.user_data_dir = user_path;
    traits.prebuilt_data_dir = prebuilt_path;
    traits.distribution_name = "Aside";
    traits.distribution_code_name = "aside";
    traits.distribution_version = "0.3.0";
    traits.app_name = "rime.aside";
    traits.min_log_level = 2;
    traits.log_dir = "";
    api->setup(&traits);
    api->initialize(&traits);
    if (api->start_maintenance(0)) api->join_maintenance_thread();
    return 1;
}
void aside_rime_finalize(void) {
    if (api) api->finalize();
    api = NULL;
    free(data_path); free(user_path); free(prebuilt_path);
    data_path = user_path = prebuilt_path = NULL;
}
uintptr_t aside_rime_create(void) {
    if (!api) return 0;
    RimeSessionId session = api->create_session();
    if (session) {
        api->select_schema(session, "aside_pinyin");
        api->set_option(session, "ascii_mode", 0);
    }
    return session;
}
void aside_rime_destroy(uintptr_t session) { if (api && session) api->destroy_session(session); }
int aside_rime_process(uintptr_t session, int key, int modifiers) { return api && session ? api->process_key(session, key, modifiers) : 0; }
int aside_rime_select(uintptr_t session, size_t index) {
    if (!api || !session) return 0;
    return api->select_candidate_on_current_page(session, index);
}
void aside_rime_highlight(uintptr_t session, size_t index) {
    if (api && session) api->highlight_candidate_on_current_page(session, index);
}
void aside_rime_commit(uintptr_t session) { if (api && session) api->commit_composition(session); }
void aside_rime_clear(uintptr_t session) { if (api && session) api->clear_composition(session); }
char *aside_rime_take_commit(uintptr_t session) {
    if (!api || !session) return NULL;
    RIME_STRUCT(RimeCommit, commit);
    if (!api->get_commit(session, &commit)) return NULL;
    char *text = commit.text ? strdup(commit.text) : NULL;
    api->free_commit(&commit);
    return text;
}
int aside_rime_context(uintptr_t session, AsideRimeContext *output) {
    memset(output, 0, sizeof(*output));
    if (!api || !session) return 0;
    RIME_STRUCT(RimeContext, context);
    if (!api->get_context(session, &context)) return 0;
    output->preedit = context.composition.preedit ? strdup(context.composition.preedit) : strdup("");
    output->cursor = context.composition.cursor_pos;
    output->highlighted = context.menu.highlighted_candidate_index;
    output->count = (size_t)context.menu.num_candidates;
    output->candidates = calloc(output->count, sizeof(char *));
    for (size_t i = 0; i < output->count; ++i) output->candidates[i] = strdup(context.menu.candidates[i].text);
    api->free_context(&context);
    return 1;
}
void aside_rime_free_context(AsideRimeContext *context) {
    free(context->preedit);
    for (size_t i = 0; i < context->count; ++i) free(context->candidates[i]);
    free(context->candidates);
    memset(context, 0, sizeof(*context));
}
void aside_rime_free_string(char *string) { free(string); }
