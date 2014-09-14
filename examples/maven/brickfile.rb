dependencies = [
    # artifact('log4j','log4j','1.2.17'),
    #artifact('jaxen','jaxen','1.1.6'),
    artifact('org.apache.tika', 'tika-xmp', '1.5', nil, nil),
    artifact('org.apache.tika', 'tika-parsers', '1.5', nil, nil)
]

rule :all => (dependencies) do
|p, n|
  echo 'JAR FILES'
  n.flatten.uniq.each { |f| echo "  #{f}" }
  nil
end
