ARG DEBIAN_RELEASE=bookworm
ARG NGINX_VERSION=1.31.6
ARG BROTLI_GIT_REF=master

FROM docker.io/library/debian:${DEBIAN_RELEASE} AS builder
ARG NGINX_VERSION
ARG BROTLI_GIT_REF

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
	build-essential git cmake curl ca-certificates libpcre2-dev zlib1g-dev libssl-dev

WORKDIR /src

RUN curl -fsSL https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz | tar -xz

RUN git init ngx_brotli && \
	cd ngx_brotli && \
	git remote add origin https://github.com/google/ngx_brotli && \
	git fetch --depth 1 origin "${BROTLI_GIT_REF}" && \
	git checkout FETCH_HEAD && \
	git submodule update --init --depth 1 && \
	git log -1 --format='ngx_brotli at %H' && \
	cd deps/brotli && mkdir out && cd out && \
	cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON .. && \
	cmake --build . --config Release --target brotlienc -j"$(nproc)" && \
	ls -l libbrotlienc.a libbrotlicommon.a

RUN cd nginx-${NGINX_VERSION} && \
	./configure --with-compat --add-dynamic-module=../ngx_brotli && \
	make -j"$(nproc)" modules && \
	ls objs/ngx_http_brotli_filter_module.so objs/ngx_http_brotli_static_module.so

# Verify
FROM docker.io/library/nginx:${NGINX_VERSION} AS test
ARG NGINX_VERSION
COPY --from=builder /src/nginx-${NGINX_VERSION}/objs/ngx_http_brotli_*.so /etc/nginx/modules/
RUN sed -i '1i load_module modules/ngx_http_brotli_filter_module.so;\nload_module modules/ngx_http_brotli_static_module.so;' /etc/nginx/nginx.conf && \
	nginx -t

FROM scratch AS export
COPY --from=test /etc/nginx/modules/ngx_http_brotli_*.so /