require_relative 'logger'
require 'fileutils'

def make_string (*args)
  args.flatten.join (' ')
end

def rm (*files)
  FileUtils.rm_rf(files)
end

def mkdirs (*files)
  FileUtils.mkdir_p(files)
end

def touch (*args)
  args.each do |name|
    _file = File.open name, mode = 'w'
    _file.close
  end
  if args.length===1 then
    args[0];
  else
    args;
  end
end

def echo (*args)
  _string = make_string args
  puts _string
  _string
end

def exec (cmdline)
  _status = 1;
  $logger.info "Execute shell command #{cmdline}"
  _result= IO.popen(cmdline, 'rt') do |io|
    _lines = io.readlines.collect { |s| s.chomp! }
    io.close
    _status = $?.to_i
    _lines
  end
  if _status != 0 then
    raise "Failed to execute command #{cmdline}"
  end
  _result
end

def shell (*args)
  # concatenate the arguments in the
  _cmdline =make_string args
  exec(_cmdline)
end

def which (*args)
  _cmdline =make_string args
  _cmdline = "which #{_cmdline}"
  _result = exec(_cmdline)
  if args.length===1 then
    _result.join
  else
    _result
  end
end

