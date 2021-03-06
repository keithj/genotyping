#-- encoding: UTF-8
#
# Copyright (c) 2012 Genome Research Ltd. All rights reserved.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

require 'fileutils'
require 'timeout'

module TestHelper
  include Genotyping

  PLINKTOOLS_DIFF = 'plink_diff.py'

  def data_path
    File.expand_path(File.join(File.dirname(__FILE__), '..', 'data'))
  end

  def manifest_path
    if ENV['GENOTYPE_TEST_DATA']
      Dir.glob(ENV['GENOTYPE_TEST_DATA']+"/*.bpm.csv").first
    end
  end

  def plex_path
    File.join(data_path, 'W30467_snp_set_info_1000Genomes.tsv')
  end

  def egt_path
    if ENV['GENOTYPE_TEST_DATA']
      Dir.glob(ENV['GENOTYPE_TEST_DATA']+"/*.egt").first
    end
  end

  def test_workflow(name, klass, timeout, path, log, args)
    ['in', 'pass', 'fail'].each do |dir|
      root = File.join(path, dir)
      FileUtils.mkdir(root) unless File.exists?(root)
    end

    yml = File.join(path, 'in', "#{name}.yml")
    File.open(yml, 'w') do |out|
      config = {'workflow' => klass.to_s,
                'arguments' => args}
      out.puts(YAML.dump(config))
    end

    percolator = Percolator.new({'root_dir' => path,
                                 'log_file' => log,
                                 'log_level' => 'DEBUG',
                                 'msg_host' => @msg_host,
                                 'msg_port' => @msg_port,
                                 'async' => 'lsf',
                                 'max_processes' => 250})

    # The Percolator returns all its workflows after each iteration
    workflow = nil
    Timeout.timeout(timeout) do
      until workflow && workflow.finished? do
        sleep(15)
        print('#')
        workflow = percolator.percolate.first
      end
    end

    workflow && workflow.passed?
  end

  def return_available?(value)
     case value
       when Array ; value.all?
       when NilClass ; nil
       else
         true
     end
   end

  def wait_for(name, timeout, interval, &test)
    result = nil

    memoizer = Percolate.memoizer
    asynchronizer = Percolate.asynchronizer
    asynchronizer.message_host = @msg_host
    asynchronizer.message_port = @msg_port
    asynchronizer.message_queue = name + '.' + $$.to_s

    Timeout.timeout(timeout) do

      begin
        until return_available?(result) do
          result = test.call
          memoizer.update_async_memos!
          sleep(interval)
          print('#')
        end
      ensure
        memoizer.update_async_memos!
      end
    end

    result
  end

  def run_test_if(predicate, msg, &test)
    if predicate.call
      test.call
    else
      $stderr.puts(msg)
    end
  end

  def make_work_dir(name, dir)
    work_dir = File.join(dir, name + '.' + $$.to_s)
    unless File.directory?(work_dir)
      Dir.mkdir(work_dir)
    end

    work_dir
   end

  def remove_work_dir(dir)
    FileUtils.rm_r(dir)
  end

  def plinktools_diff_available?()
    system("which #{PLINKTOOLS_DIFF} >/dev/null 2>&1")
  end

  def plink_equivalent?(stem, master, run_name, args = {})
    # check equivalence of two plink stems using plinktools diff
    # use to verify that test output is equivalent to master
    args, work_dir, log_dir = process_task_args(args)
    if args_available?(run_name, work_dir)
      unless plinktools_diff_available?()
        raise "Cannot find Plinktools diff script; requires an installation of Plinktools >= 0.4.1 on the PATH"
      end

      out_stem = File.join(work_dir, run_name+'.plink_test')
      cli_args = args.merge({:in1 => stem,
                             :in2 => master,
                             :out => out_stem})
      margs = [cli_args, work_dir]

      command = [PLINKTOOLS_DIFF,
                 cli_arg_map(cli_args, :prefix => '--')].flatten.join(' ')
      summary = out_stem+"_summary.json"
      task(margs, command, work_dir,
           :post => lambda { ensure_files([summary], :error => false) },
           :result => lambda { summary })
      summary_data = JSON.parse(File.read(summary))
      result = summary_data[0]["EQUIVALENT"]
      return result
    end

  end

end
