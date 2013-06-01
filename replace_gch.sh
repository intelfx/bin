
#!/bin/bash

while read name; do
	echo $name
	ln -sf /tmp/${name//\//-}.gch $name.gch
done < <(find ${1:-.} -name 'stdafx.h' -print)
