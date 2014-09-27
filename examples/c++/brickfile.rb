# this target lists the sources
rule :sources do
  shell 'find src -name \*.cpp -o -name \*.h'
end

# this target makes source names into corresponding object files
rule :objects => :sources do
|p,needs|
  _objects = [];

  needs[0].each do |s|
    if s.end_with? '.cpp' then 
      _objects << (s.gsub('.cpp', '.o').gsub(/^src/,'objects'))
    end
  end
  _objects
end

depends 'objects/%.o' => 'brickfile.rb' 


# this rule builds an object file from a source file
rule 'objects/%.o' => 'src/{1}.cpp' do
|p, n|
  mkdirs p.directory
  echo "Compiling #{p}"
  shell "g++ -c -o #{p} #{n[0]}"
  p.file
end

# rule to build the main executable from the objects
# we use the dependency_of metadependency, which will 
# treat the out of the objects target as dependencies
rule 'main' => dependency_of(:objects) do
|p, n|
  echo "Linking #{n.flatten.join(' ')}"
  shell "g++ -o #{p} #{n.flatten.join(' ')}"
  'main'
end

rule :all => 'main' do
  |p,n|
  shell "#{n[0]} 'Hello, World'"
end

rule :clean => :objects do
  |p,objects|
  rm(*objects[0])
  rm('main','objects')
end
