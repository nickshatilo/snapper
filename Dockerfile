FROM node:20-alpine AS build
WORKDIR /app
COPY website/package*.json ./
RUN npm install
COPY website/ .
RUN npm run build

FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
