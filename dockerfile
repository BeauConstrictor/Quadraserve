from debian:bookworm-slim

run apt update
run apt install -y nim make

workdir /app
copy . .

run make

expose 70
expose 79
expose 80
expose 1965

cmd ["./serve"]