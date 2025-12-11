nerdctl run -d --name sst-aptly-server -p 8080:80 \
  -v ~/sw/sst-aptly/public:/usr/share/nginx/html:ro \
  docker.io/library/nginx:alpine
