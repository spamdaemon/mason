rule :win32 do
  echo 'The win32'
  raise 'Unsupported architecture'
end

rule :linux do
  echo 'The Linux'
  'LINUX'
end


(rule({:gates => :linux, :produces => 'foo'}) do
  echo 'Compiling for LINUX'
  touch 'foo'
end)

(rule({
         :gates => :win32,
         :produces => 'foo'}) do

  echo 'Compiling for WIN32'
  touch 'foo'
end)


# this target lists the sources
rule :arch => architecture do
|p, arch|
  arch
end

rule :compiler do
  _result=nil
  begin
    _result= (which 'gcc')
  rescue
    _result= (which 'clang')
  end
  _result
end


rule :all => ['foo', :arch, :compiler] do
|p, depends|
  echo depends[0]
  echo depends[1]
end

