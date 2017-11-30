
if [ $# -eq 0 ]; then
	PLATFORM="x86_64-linux"
else
	PLATFORM="$1"
fi

echo "${PLATFORM}"

# {"version": "1.2.89", "sha1": "5ca3dd134cc960c35ecefe12f6dc81a48f212d40"}
SHA1=$(curl -s http://d.defold.com/stable/info.json | sed 's/.*sha1": "\(.*\)".*/\1/')
echo "Using Defold dmengine_headless version ${SHA1}"

#DMENGINE_URL="http://d.defold.com/archive/${SHA1}/engine/linux/dmengine_headless"
DMENGINE_URL="http://d.defold.com/archive/${SHA1}/engine/${PLATFORM}/dmengine_headless"
BOB_URL="http://d.defold.com/archive/${SHA1}/bob/bob.jar"

echo "Downloading ${DMENGINE_URL}"
curl -o dmengine_headless ${DMENGINE_URL}
chmod +x dmengine_headless

echo "Downloading ${BOB_URL}"
curl -o bob.jar ${BOB_URL}

if [ -n "${DEFOLD_AUTH}" ] && [ -n "${DEFOLD_USER}" ]; then
	echo "Running bob.jar - resolving dependencies"
	java -jar bob.jar --auth "${DEFOLD_AUTH}" --email "${DEFOLD_USER}" resolve
fi

echo "Running bob.jar - building"
java -jar bob.jar --debug build

echo "Starting dmengine_headless"
./dmengine_headless
