# ---------- Stage 1: build with npm ----------
FROM node:20-alpine AS build
WORKDIR /build

# package.json first -> layer caching for npm install
COPY package.json ./
RUN npm install

COPY . .
RUN npm run build

# ---------- Stage 2: serve with nginx ----------
FROM nginx:1.27-alpine
COPY --from=build /build/build /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

# nginx:alpine already runs worker processes as non-root "nginx" user internally;
# expose on 8080 (non-privileged port) so the container itself can run as non-root too.
EXPOSE 8080
