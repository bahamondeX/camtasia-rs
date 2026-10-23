#include <stdint.h>
void *editor_create(void);
void editor_destroy(void *handle);
char *editor_execute(void *handle, const char *request);
void editor_free(char *response);
