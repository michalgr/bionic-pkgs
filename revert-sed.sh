git commit --allow-empty -m "Revert experimental \`sed\` filters for \`NIX_LDFLAGS\`

This reverts the experimental \`sed\` filters. As verified during CI builds and user testing, stripping \`-L/usr/lib\` from \`NIX_LDFLAGS\` inside the setup hook is ineffective because the Nixpkgs Darwin \`cc-wrapper\` reads from its internal \`libc-ldflags\` file and forcibly injects the host library paths directly into the linker invocation regardless of the environment variables.
"
