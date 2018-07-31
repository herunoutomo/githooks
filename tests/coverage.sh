#!/bin/sh

# Build a Docker image on top of kcov with our scripts
cat <<EOF | docker build --force-rm -t githooks:coverage -f - .
FROM ragnaroek/kcov:v33

RUN apt-get update && apt-get install -y --no-install-recommends git

ADD base-template.sh install.sh uninstall.sh /var/lib/githooks/

RUN git config --global user.email "githook@test.com" && \
    git config --global user.name "Githook Tests"

ADD tests/exec-steps.sh tests/step-* tests/replace-template-loader.py /var/lib/tests/

# Some fixup below:
# Make sure we're using Bash for kcov
RUN find /var/lib -name '*.sh' -exec sed -i 's|#!/bin/sh|#!/bin/bash|g' {} \\; && \\
    find /var/lib -name '*.sh' -exec sed -i 's|sh /|bash /|g' {} \\; && \\
    find /var/lib -name '*.sh' -exec sed -i 's|sh "|bash "|g' {} \\; && \\
# Replace the inline template with loading the base template file
    python /var/lib/tests/replace-template-loader.py /var/lib/githooks && \\
# Change the base template so we can pass in the hook name
    sed -i 's|^HOOK_NAME=.*|HOOK_NAME=\${HOOK_NAME:-\$(basename "\$0")}|' /var/lib/githooks/base-template.sh && \\
    sed -i 's|^HOOK_FOLDER=.*|HOOK_FOLDER=\${HOOK_FOLDER:-\$(dirname "\$0")}|' /var/lib/githooks/base-template.sh
EOF

# shellcheck disable=SC2181
if [ $? -ne 0 ]; then
    exit 1
fi

# Make sure we delete the previous run results
docker run --security-opt seccomp=unconfined \
    -v "$PWD/cover":/cover \
    --entrypoint sh \
    githooks:coverage \
    -c 'rm -rf /cover/*'

# Run the actual tests and collect the coverage info
docker run --security-opt seccomp=unconfined \
    -v "$PWD/cover":/cover \
    githooks:coverage \
    --coveralls-id="$TRAVIS_JOB_ID" \
    --include-pattern="/var/lib/githooks/" \
    /cover \
    /var/lib/tests/exec-steps.sh