# frontend/Dockerfile  (Vue CLI ili Vite – pokrit ćemo oba)
FROM node:20-bullseye AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
# build-time var za oba svijeta (Vite i Vue CLI)
ENV VITE_API_BASE=/api
ENV VUE_APP_API_BASE=/api
RUN npm run build

FROM nginx:alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
