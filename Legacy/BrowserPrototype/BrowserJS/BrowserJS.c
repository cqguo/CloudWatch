#include "include/BrowserJS.h"
#include "quickjs.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
typedef struct CWRejection { JSValue promise, reason; struct CWRejection *next; } CWRejection;
struct CWJS { JSRuntime *rt; JSContext *ctx; double deadline; CWParseHTML parse; CWRejection *rejections; };
static void rejection_tracker(JSContext *ctx, JSValueConst promise, JSValueConst reason, JS_BOOL handled, void *opaque) {
    CWJS *e = opaque;
    if (handled) {
        CWRejection **slot = &e->rejections;
        while (*slot) {
            CWRejection *r = *slot;
            if (JS_VALUE_GET_PTR(r->promise) == JS_VALUE_GET_PTR(promise)) {
                *slot = r->next; JS_FreeValue(ctx,r->promise); JS_FreeValue(ctx,r->reason); free(r); return;
            }
            slot = &r->next;
        }
    } else {
        CWRejection *r = malloc(sizeof(*r));
        if (!r) return;
        r->promise = JS_DupValue(ctx,promise); r->reason = JS_DupValue(ctx,reason);
        r->next = e->rejections; e->rejections = r;
    }
}
static void clear_rejections(CWJS *e) {
    while (e->rejections) { CWRejection *r=e->rejections; e->rejections=r->next;
        JS_FreeValue(e->ctx,r->promise); JS_FreeValue(e->ctx,r->reason); free(r); }
}
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }
static int interrupt(JSRuntime *rt, void *opaque) { return now() > ((CWJS *)opaque)->deadline; }
static JSValue parse_html(JSContext *ctx, JSValueConst self, int argc, JSValueConst *argv) {
    CWJS *e = JS_GetContextOpaque(ctx);
    const char *html = JS_ToCString(ctx, argc ? argv[0] : JS_UNDEFINED);
    if (!html) return JS_EXCEPTION;
    if (strlen(html) > 2000000) { JS_FreeCString(ctx, html); return JS_ThrowRangeError(ctx, "HTML exceeds 2 MB"); }
    char *json = e->parse(html); JS_FreeCString(ctx, html);
    if (!json) return JS_ThrowInternalError(ctx, "HTML parsing failed");
    JSValue result = JS_ParseJSON(ctx, json, strlen(json), "html-tree"); free(json); return result;
}
CWJS *cwjs_create(size_t limit, CWParseHTML parse) {
    CWJS *e = calloc(1, sizeof(*e)); if (!e) return NULL;
    e->rt = JS_NewRuntime(); if (!e->rt) { free(e); return NULL; }
    JS_SetMemoryLimit(e->rt, limit); JS_SetMaxStackSize(e->rt, 512 * 1024);
    e->ctx = JS_NewContext(e->rt); if (!e->ctx) { JS_FreeRuntime(e->rt); free(e); return NULL; }
    e->parse = parse; JS_SetContextOpaque(e->ctx, e); JS_SetInterruptHandler(e->rt, interrupt, e);
    JS_SetHostPromiseRejectionTracker(e->rt, rejection_tracker, e);
    JSValue global = JS_GetGlobalObject(e->ctx);
    JS_SetPropertyStr(e->ctx, global, "__parseHTML", JS_NewCFunction(e->ctx, parse_html, "__parseHTML", 1));
    JS_FreeValue(e->ctx, global); return e;
}
void cwjs_destroy(CWJS *e) { if (!e) return; clear_rejections(e); JS_FreeContext(e->ctx); JS_FreeRuntime(e->rt); free(e); }
char *cwjs_eval(CWJS *e, const char *script, const char *filename, int *failed) {
    *failed = 0; e->deadline = now() + 0.5;
    JS_UpdateStackTop(e->rt);
    JSValue result = JS_Eval(e->ctx, script, strlen(script), filename, JS_EVAL_TYPE_GLOBAL);
    if (JS_IsException(result)) { *failed = 1; result = JS_GetException(e->ctx); }
    if (!*failed) {
        JSContext *jobctx; int jobs = 0, status;
        while ((status = JS_ExecutePendingJob(e->rt, &jobctx)) > 0) {
            if (++jobs > 1000 || now() > e->deadline) { *failed = 1; JS_FreeValue(e->ctx, result); return strdup("JavaScript microtask budget exceeded"); }
        }
        if (status < 0) { *failed = 1; JS_FreeValue(e->ctx, result); result = JS_GetException(jobctx); }
    }
    if (!*failed && e->rejections) { *failed = 1; JS_FreeValue(e->ctx,result); result = JS_DupValue(e->ctx,e->rejections->reason); }
    clear_rejections(e);
    const char *value = JS_ToCString(e->ctx, result);
    char *copy = strdup(value ? value : "JavaScript exception (no message)");
    if (*failed && JS_IsObject(result)) {
        JSValue stack = JS_GetPropertyStr(e->ctx, result, "stack");
        const char *trace = JS_ToCString(e->ctx, stack);
        if (trace && strcmp(trace, "undefined")) {
            size_t size = strlen(copy) + strlen(trace) + 2;
            char *detail = malloc(size);
            if (detail) { snprintf(detail, size, "%s\n%s", copy, trace); free(copy); copy = detail; }
        }
        if (trace) JS_FreeCString(e->ctx, trace); JS_FreeValue(e->ctx, stack);
    }
    if (value) JS_FreeCString(e->ctx, value); JS_FreeValue(e->ctx, result); return copy;
}
void cwjs_free_string(char *text) { free(text); }
