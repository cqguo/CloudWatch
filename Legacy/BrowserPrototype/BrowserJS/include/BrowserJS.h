#ifndef CW_BROWSER_JS_H
#define CW_BROWSER_JS_H
#include <stddef.h>
typedef struct CWJS CWJS;
// Callback returns malloc-owned JSON. No network or filesystem capability is exposed.
typedef char *(*CWParseHTML)(const char *html);
CWJS *cwjs_create(size_t memory_limit, CWParseHTML parse);
void cwjs_destroy(CWJS *engine);
char *cwjs_eval(CWJS *engine, const char *script, const char *filename, int *failed);
void cwjs_free_string(char *text);
#endif
