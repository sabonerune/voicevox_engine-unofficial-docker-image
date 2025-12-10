#include <stdio.h>
#include <unistd.h>

int main(int argc, char *argv[])
{
  if (argc < 3)
  {
    fprintf(stderr, "entrypoint: no input files\n");
    return 1;
  }
  const char *readmePath = argv[1];
  FILE *f = fopen(readmePath, "r");
  if (!f)
  {
    perror("entrypoint");
    fprintf(stderr, "Failed to read: \'%s\'\n", readmePath);
    return 1;
  }
  char buf[512];
  while (fgets(buf, sizeof(buf), f))
  {
    fputs(buf, stderr);
  }
  fclose(f);
  const char *enginePath = argv[2];
  execv(enginePath, &argv[2]);
  perror("entrypoint");
  fprintf(stderr, "Failed to exec: \'%s\'\n", enginePath);
  return 1;
}
