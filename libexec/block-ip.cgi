echo "Status: 410 Gone"
echo "Content-type: text/plain"
echo "Connection: close"
echo

echo "Bye bye, $REMOTE_ADDR!"
sudo /usr/local/libexec/block-ip.sh

exit 0
