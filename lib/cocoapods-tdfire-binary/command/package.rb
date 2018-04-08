require 'colored2'
require 'fileutils'
require 'cocoapods-tdfire-binary/binary_url_manager'
require 'cocoapods-tdfire-binary/binary_specification_refactor'

module Pod
	class Command
		class Binary < Command
			class Package < Binary 
        self.abstract_command = false
				self.summary = '二进制打包'
				self.description = <<-DESC
					将源码打包成二进制，并压缩成 zip 包
	      DESC

	      def self.options
          [
            ['--clean', '执行成功后，删除 zip 文件外的所有生成文件'],
            ['--spec-sources', '私有源地址'],
          ].concat(super)
        end

	      def initialize(argv)
	      	@clean = argv.flag?('clean')
	      	@spec_sources = argv.option('spec-sources')
	      	@spec_file = first_podspec
	      	super
	      end

        def validate!
          super
          help! '当前目录下没有podspec文件.' if @spec_file.nil?
        end

        def run
        	spec = Specification.from_file(@spec_file)
        	package(spec)
        	zip(spec)
        end

        private

        def package(spec)
        	UI.section("Tdfire: package #{spec.name} ...") do
	        	system "pod package #{spec.name}.podspec --exclude-deps --force --no-mangle --spec-sources=#{@spec_sources || Tdfire::BinaryUrlManager.private_cocoapods_url}"
	        end
        end

        def zip(spec)
					framework_directory = "#{spec.name}-#{spec.version}/ios"
					framework_name = "#{spec.name}.framework"
					framework_path = "#{framework_directory}/#{framework_name}"

        	raise Informative, "没有需要压缩的 framework 文件：#{framework_path}" unless File.exist?(framework_path)

					# cocoapods-packager 使用了 --exclude-deps 后，虽然没有把 dependency 的符号信息打进可执行文件，但是它把 dependency 的 bundle 给拷贝过来了 (builder.rb 229 copy_resources)
					# 这里把多余的 bundle 删除
					# https://github.com/CocoaPods/cocoapods-packager/pull/199
					resource_bundles = spec.all_hash_value_for_attribute('resource_bundles').keys.flatten.uniq
					FileUtils.chdir("#{framework_path}/Versions/A/Resources") do
						dependency_bundles = Dir.glob('*.bundle').select { |b| !resource_bundles.include?(b.split('.').first) }
						unless dependency_bundles.empty?
							Pod::UI::puts "Tdfire: remove dependency bundles: #{dependency_bundles.join(', ')}"

							dependency_bundles.each do |b|
								FileUtils.rm_rf(b)
							end
						end
					end if File.exist? "#{framework_path}/Versions/A/Resources"

        	output_name = "#{framework_name}.zip"
        	UI.section("Tdfire: zip #{framework_path} ...") do
						FileUtils.chdir(framework_directory) do
							system "zip --symlinks -r #{output_name} #{framework_name}"
							system "mv #{output_name} ../../"
						end
					end

					Pod::UI::puts "Tdfire: save framework zip file to #{Dir.pwd}/#{output_name}".green

					system "rm -fr #{spec.name}-#{@spec.version}" if @clean
        end

			end
		end
	end
end