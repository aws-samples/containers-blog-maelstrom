#!/bin/bash
#To make the image size artificially large, I will include twenty 50 MB files. 
# Lets generate large files containing random text:# create the 'files' directory if it doesn't already exist
if [ ! -d "files" ]; then
    mkdir files 
fi
# create 20 50 MB files in the 'files' directory
for tag in {1..20}; do
    dd if=/dev/urandom of=files/large_file_$tag.txt bs=1048576 count=50 
done
#Create Docker File
cat > Dockerfile <<EOL
FROM debian
RUN apt-get update && apt-get install -y \
vim
COPY files .
EOL
# Build the Docker image using the Dockerfile in the current directory
docker build -t $EDP_NAME .
docker tag $EDP_NAME $EDP_AWS_ACCOUNT.dkr.ecr.$EDP_AWS_REGION.amazonaws.com/$EDP_NAME

# Check if the build was successful
if [ $? -eq 0 ]; then
echo "Docker image '$EDP_NAME' built successfully."
else
echo "Docker image '$EDP_NAME' build failed."
fi
