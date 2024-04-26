# Run with
# sudo docker build --build-arg GITHUB_TOKEN=MY_GITHUB_TOKEN --secret id=ssh_key,src=/home/dev/.ssh/id_ed25519 --progress=plain  --build-arg CACHEBUST=$(date +%s)  -t localhost:5100/app1:release .
# where id_ed25519 is ssh private key registered with Github
# and localhost:5100 is the target Docker repo

# Push to repo after this with 
# sudo docker push localhost:5100/app1:release



# Use a Python image to compile the application
FROM python:3.11.9 as builder

WORKDIR /app

RUN echo "deb http://deb.debian.org/debian bookworm-backports main" | tee -a /etc/apt/sources.list

# Install git and Nuitka
RUN apt-get update && apt-get install -y \
    git openssh-client patchelf zlib1g upx-ucl/bookworm-backports\
    && pip install nuitka

# Ensure ssh directory is setup
RUN mkdir -p ~/.ssh && chmod 700 ~/.ssh

# Use the SSH key during the build
RUN --mount=type=secret,id=ssh_key \
    cp /run/secrets/ssh_key ~/.ssh/id_rsa && \
    chmod 600 ~/.ssh/id_rsa && \
    ssh-keyscan github.com >> ~/.ssh/known_hosts

# Declare the argument GITHUB_TOKEN
ARG GITHUB_TOKEN

# Setup git to use the GitHub token for private repository access
RUN echo "machine github.com login $GITHUB_TOKEN" > ~/.netrc

# Clone and prepare application
RUN git clone --recurse-submodules https://github.com/nrodichenko/cd-test-release.git .

RUN pip install -r cd-test-app1/requirements.txt

RUN python -m nuitka \
        --standalone \
        --nofollow-import-to=pytest \
        --python-flag=nosite,-O \
        --plugin-enable=anti-bloat,implicit-imports,data-files,pylint-warnings \
        --warn-implicit-exceptions \
        --warn-unusual-code \
        --prefer-source-code \
        cd-test-app1/app1.py

# ARG CACHEBUST=1 

RUN ldd ./app1.dist/app1.bin | grep "=> /" | awk '{print $3}' | xargs -I '{}' cp --no-clobber -v '{}' ./app1.dist
RUN ldd ./app1.dist/app1.bin | grep "/lib64/ld-linux-x86-64" | awk '{print $1}' | xargs -I '{}' cp --parents -v '{}' ./app1.dist
RUN cp --no-clobber -v /lib/x86_64-linux-gnu/libgcc_s.so.1 ./app1.dist
RUN mkdir -p ./app1.dist/lib/x86_64-linux-gnu/
RUN cp --no-clobber -v /lib/x86_64-linux-gnu/libresolv* ./app1.dist/lib/x86_64-linux-gnu
RUN cp --no-clobber -v /lib/x86_64-linux-gnu/libnss_dns* ./app1.dist/lib/x86_64-linux-gnu
RUN cp /usr/lib/x86_64-linux-gnu/libz.so.1 ./app1.dist/
RUN upx -9 ./app1.dist/app1.bin

RUN ls ./app1.dist/

# Start from a scratch image
FROM scratch

# Copy the compiled binary
COPY --from=builder /app/app1.dist/ /

# Command to run the application
CMD ["/app1.bin"]
