
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
DMENGINE_FILE=dmengine_headless_${SHA1}
BOB_FILE=bob_${SHA1}.jar

# Download dmengine_headless
if ! [ -f ${DMENGINE_FILE} ]; then
	echo "Downloading ${DMENGINE_URL} to ${DMENGINE_FILE}"
	curl -L -o ${DMENGINE_FILE} ${DMENGINE_URL}
	chmod +x ${DMENGINE_FILE}
fi

# Download bob.jar
if ! [ -f ${BOB_FILE} ]; then
	echo "Downloading ${BOB_URL} to ${BOB_FILE}"
	curl -L -o ${BOB_FILE} ${BOB_URL}
fi

# Fetch libraries
echo "Running ${BOB_FILE} - resolving dependencies"
java -jar ${BOB_FILE} --auth "foobar" --email "john@doe.com" resolve

echo "Running ${BOB_FILE} - building"
java -jar ${BOB_FILE} --debug build --settings=test.settings

echo "Starting ${DMENGINE_FILE}"
./${DMENGINE_FILE}
