
if [ $# -eq 0 ]; then
	PLATFORM="x86_64-linux"
else
	PLATFORM="$1"
fi


echo "${PLATFORM}"

# {"version": "1.2.89", "sha1": "5ca3dd134cc960c35ecefe12f6dc81a48f212d40"}
# Get SHA1 of the current Defold stable release
SHA1=$(curl -s http://d.defold.com/stable/info.json | sed 's/.*sha1": "\(.*\)".*/\1/')
echo "Using Defold dmengine_headless version ${SHA1}"

# Create dmengine_headless and bob.jar URLs
DMENGINE_URL="http://d.defold.com/archive/${SHA1}/engine/${PLATFORM}/dmengine_headless"
BOB_URL="http://d.defold.com/archive/${SHA1}/bob/bob.jar"

# Download dmengine_headless
echo "Downloading ${DMENGINE_URL}"
curl -L -o dmengine_headless ${DMENGINE_URL}
chmod +x dmengine_headless

# Download bob.jar
echo "Downloading ${BOB_URL}"
curl -L -o bob.jar ${BOB_URL}

# Fetch libraries
echo "Running bob.jar - resolving dependencies"
java -jar bob.jar --auth "foobar" --email "john@doe.com" resolve

echo "Running bob.jar - building"
java -jar bob.jar --debug build --keep-unused

echo "Starting dmengine_headless"
if [ -n "${DEFOLD_BOOSTRAP_COLLECTION}" ]; then
	./dmengine_headless --config=bootstrap.main_collection=${DEFOLD_BOOSTRAP_COLLECTION}
else
	./dmengine_headless
fi
