cd ./source
zip -r ../code.zip *
cd ..

aws lambda update-function-code \
--function-name HelloWorld_Lambda_Function \
--region us-east-1 \
--zip-file fileb://code.zip

rm code.zip