module Embulk
  class InputJstat < InputPlugin
    require 'json'

    Plugin.register_input('jstat', self)

    # output columns of jstat (JDK8)
    JSTAT_COLUMNS = {
      class: {
        Loaded: 'int',
        Bytes: 'double',
        Unloader: 'int',
        Bytes: 'double',
        Time: 'double'
      },
      compiler: {
        Compiled: 'int',
        Failed: 'int',
        Invalid: 'int',
        Time: 'double',
        FailedType: 'int',
        FailedMethod: 'string'
      },
      gc: {
        S0C: 'double',
        S1C: 'double',
        S0U: 'double',
        S1U: 'double',
        EC: 'double',
        EU: 'double',
        OC: 'double',
        MC: 'double',
        MU: 'double',
        CCSC: 'double',
        CCSU: 'double',
        YGC: 'int',
        YGCT: 'double',
        FGC: 'int',
        FGCT: 'double',
        GCT: 'double'
      },
      gccause: {
        S0: 'double',
        S1: 'double',
        E: 'double',
        O: 'double',
        M: 'double',
        CCS: 'double',
        YGC: 'int',
        YGCT: 'double',
        FGC: 'int',
        FGCT: 'double',
        GCT: 'double',
        LGCC: 'string',
        GCC: 'string'
      },
      gcnew: {
        S0C: 'double',
        S1C: 'double',
        S0U: 'double',
        S1U: 'double',
        TT: 'int',
        MTT: 'double',
        DSS: 'double',
        EC: 'double',
        EU: 'double',
        YGC: 'int',
        YGCT: 'double'
      },
      gcnewcapacity: {
        NGCMN: 'double',
        NGCMX: 'double',
        NGC: 'double',
        S0CMX: 'double',
        S0C: 'double',
        S1CMX: 'double',
        S1C: 'double',
        ECMX: 'double',
        EC: 'double',
        YGC: 'int',
        FGC: 'int'
      },
      gcold: {
        MC: 'double',
        MU: 'double',
        CCSC: 'double',
        CCSU: 'double',
        OC: 'double',
        OU: 'double',
        YGC: 'int',
        FGC: 'int',
        FGCT: 'double',
        GCT: 'double'
      },
      gcoldcapacity: {
        OGCMN: 'double',
        OGCMX: 'double',
        OGC: 'double',
        OC: 'double',
        YGC: 'int',
        FGC: 'int',
        FGCT: 'double',
        GCT: 'double'
      },
      gcmetacapacity: {
        MCMN: 'double',
        MCMX: 'double',
        MC: 'double',
        CCSMN: 'double',
        CCSMX: 'double',
        CCSC: 'double',
        YGC: 'int',
        FGC: 'int',
        FGCT: 'double',
        GCT: 'double'
      },
      gcutil: {
        S0: 'double',
        S1: 'double',
        E: 'double',
        O: 'double',
        M: 'double',
        CCS: 'double',
        YGC: 'int',
        YGCT: 'double',
        FGC: 'int',
        FGCT: 'double',
        GCT: 'double'
      },
      printcompilation: {
        Compiled: 'int',
        Size: 'int',
        Type: 'int',
        Method: 'string'
      }
    }

    def self.transaction(config, &control)
      paths = config.param('paths', :array, default: ['/tmp']).map { |path|
        next [] unless Dir.exists?(path)
        Dir.entries(path).sort.select{|f| f.match(/^.+\.log$/)}.map do |file|
          File.expand_path(File.join(path, file))
        end
      }.flatten

      #TODO: erase default when the debug is finished.
      option = config.param('option', :string, default: 'gcutil')
      if option =~ /^\-/
        option[0] = ''
      end
      if !JSTAT_COLUMNS.has_key?(option.to_sym)
        raise "Unknown option: #{option}. Specify a stat option of jstat correctly."
      end

      threads = config.param('threads', :integer, default: 1)

      columns = JSTAT_COLUMNS[option.to_sym].each_with_index.map do |column, index|
        stat, type = column
        case type
        when "string"
          Column.new(index, stat.to_s, :string)
        when "int", "long"
          Column.new(index, stat.to_s, :long)
        when "double", "float"
          Column.new(index, stat.to_s, :double)
        end
      end

      task = {'paths' => paths}

      commit_reports = yield(task, columns, threads)
      puts "Commit reports = #{commit_reports.to_json}"

      return {}
    end

    def initialize(task, schema, index, page_builder)
      super
    end

    def run
      paths = @task['paths']
      not_jstat_files = []

      paths.each do |path|
        File.read(path).each_line do |line|
          stats = line.strip.split(/\s+/)

          # maybe not jstat file if a number of column is not match.
          if stats.size != @schema.size
            not_jstat_files << path
            break
          end

          # ignore column heading line
          next unless stats[0] != @schema[0]['name']

          page = []
          @schema.each_with_index do |s, i|
            case s['type']
            when :string
              page << stats[i]
            when :long
              page << stats[i].to_i
            when :double
              page << stats[i].to_f
            else
              raise "unknown type: #{s['type']}"
            end
          end
          @page_builder.add(page)
        end
      end
      @page_builder.finish

      {  # commit report
        "commited_jstat_files" => paths - not_jstat_files
      }
    end
  end
end
