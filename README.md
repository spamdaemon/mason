mason
=====

A simple make replacement written in Ruby


Motiviation
===========

At this momement, this is just a prototype to sketch out some ideas I've had regarding how I want to build. I still believe that the original make or gnumake are the best approach for building software, but they have some obvious drawbacks, as we all know. Newer replacements like ant or maven are very successful, but I find their declarative approach too constrained. 
So, I thought, let's see if I can't build a protoype in Ruby, so I can swat to birds with one stone: figure out how hard it actually is build a decent make replacement, and learn Ruby at the same time.

Here is a simple example of building with a bunch of C sources with gcc on a Linux system. 
```rb
rule :all => 'main'

rule :sources do
  shell "find . -name \*.src"
end

rule :objects => :sources do
  |product,sources|
  _result = []
  sources.flatten.each do |src| 
    if src.end_with? '.cpp' then
      _result.push(src.gsub('.cpp','.o'))
    end
  end
  Dependency.create(_result)
end


rule 'main' => :objects do
  | product,objects|
  _objects = objects.flatten.join(' ')
  shell "gcc -o #{product.file} #{_objects}"
  product
end


rule '%.o' => '{1}.c' do
  | product,needs|
  shell "gcc -c -o #{product.file} #{needs[0]}"
  product
end
```

Usage
=====

I call this tool mason and the buildscript resides in a brickfile.rb (using the rb extension allows the editor to mark it up in Ruby). The brickfile itself is just a Ruby script, which means you have the full capabilities of ruby at your disposal. 


The building block of brickfile is the rule. Just like in make, a rule has this basic form:
```rb
rule product => dependencies do
  |product,needs|
  ....
end
```

On the left-hand side of a rule is the product specification (spec). The product spec defines what it is that the rule will build. A spec can be a string or a regular expression, both of which are interpreted as filenames, or it can be a symbol, which is termed a target. More complex specs are also possible by creating your own Spec implementation, but more on that later.

On the right-hand side of a rule we have the dependencies, which are specs of the products that are required by the rule before it can be applied. There can be more than one dependency.

The steps executed by the rule are defined between the ```do |product,deps| .... end```. For those who know Ruby, this is a just a Ruby block. The ``` |product,deps|``` are variables that are bound to the dependency that will be resolved once the product is built, and the results from evaluating the rule's dependencies, respectively. Currently, the ```deps``` is always an array. ```product``` is always a Dependency, and ````deps``` is always an array of values. Consider this example:
```rb
rule 'object/main.o' => 'src/main.c' do | product, deps | 
  shell "gcc -o #{product.file} #{needs[0]}"
  product.file
```

The product is bound to a file dependency, which is has the ```file``` attribute, but the dependencies are bound to the actual filenames, i.e. ```needs[0]==='src/main.c'```


Left-hand side specs may define variables, which will be resolved when a rule is determined to be a match for a dependency. Those variables are then applied to the specs on the right-hand side to generate specific dependencies. The rule for binding variables depends on the particular spec itself. For example, when using files on the left-hand side, when can use ```'objects/%/%.%'``` to define three variables, indexed as 1, 2, and 3. When using files on the right-hand side, we can reference these variables ```sources/{1}/{2}.{3}```. The special variable ```{0}``` defines the string for the entire left-hand side. Note that the notation ```%``` is actually short-hand for a regular-expression ```(.+)```. Specifying a string containing ```%``` turns the string into a properly quoted regular expression.


Once the rule has finished, the value that should be associated with the product must be returned. This is somewhat different from make, where everything is a file. Since we have other types of products, we must explicitly return the product value. The value that is being returned will become a ```deps``` for another rule! 
It is allowed, to return a new dependency from a rule, which has the effect of making that dependency before the rule has finished.


There are two caveats when creating rules:

1. There must only be one rule that can build a dependency.
2. Rules and their dependencies must form a acyclic graph (DAG).

The acyclic requirement can be tricky, especially when there are rules that return dependencies.
