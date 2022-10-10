# create a new container to perform the build stage
FROM node:16-alpine3.15 as build-stage

# set the working directory for the container to "/frontend_source"
WORKDIR /frontend_source

# copy the project into the build-stage container at "/frontend_source"
COPY ./ /frontend_source

# run the following commands to install dependencies, build project
# these run *inside* the build-stage container
RUN npm install
RUN npm run build

# create a new container based off nginx
FROM nginx:1.23

# copy the react app binary from the "build-stage" container into the new
# nginx-based container
COPY --from=build-stage /frontend_source/build/ /usr/share/nginx/html

# copy a static resource "nginx.conf" into the nginx-based container to set up
# nginx with the configuration that we want
#COPY docker_resources/nginx.conf /etc/nginx/conf.d/default.conf

# that's it! now you have a docker image that's ready to host your react
# frontend with a configured nginx webserver
