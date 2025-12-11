#!/bin/bash 
# 1. Create the logical repo inside aptly's database
nerdctl run --rm -v ~/sw//sst-aptly/db:/.aptly \
  aptly/aptly:latest \
  repo create -distribution=bookworm -component=main sst-local

# 2. Add all .deb files from your /inbox
nerdctl run --rm -v ~/sw/sst-aptly/inbox:/inbox -v ~/sst-aptly/db:/.aptly \
  aptly/aptly:latest \
  repo add sst-local /inbox

# 3. "Publish" the repo. This creates the real file structure in /public
nerdctl run --rm -v ~/sw/sst-aptly/db:/.aptly -v ~/sst-aptly/public:/public \
  aptly/aptly:latest \
  publish repo -architectures="amd6N_64,arm64" sst-local /public
