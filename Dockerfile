# base image
FROM node:16-alpine3.16

# set working directory
WORKDIR /app

# copy package.json and package-lock.json
COPY package*.json ./

# install dependencies
RUN npm install

# copy source code
COPY . .

# build the app
RUN npm run build

# expose the port
EXPOSE 3000

# start the server
CMD ["node", "build/index.js"]
