#--
# Copyright (C) 2007-2017 Harald Sitter <sitter@kde.org>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of
# the License or (at your option) version 3 or any later version
# accepted by the membership of KDE e.V. (or its successor approved
# by the membership of KDE e.V.), which shall act as a proxy
# defined in Section 14 of version 3 of the license.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#++

require_relative 'archive_signer'
require_relative 'documentation'
require_relative 'hash_template'
require_relative 'jenkins'
require_relative 'l10n'
require_relative 'logable'
require_relative 'source'
require_relative 'template'
require_relative 'xzarchive'

# FIXME: with vcs construction outside the class scope there need to be tests
#        that run a Release with all possible Vcs derivates!
# FIXME: because so much stuff happens outside this class is really incredibly
#        useless

module ReleaseMe
  class Release
    prepend Logable

    # The vcs from which to get the source
    attr_reader :project
    # The origin to release from
    attr_reader :origin
    # The version to release
    attr_reader :version
    # The source object from which the release is done
    attr_reader :source
    # The archive object which will create the archive
    attr_reader :archive_

    # Init
    # @param project [Project] the Project to release
    # @param origin [Symbol] the origin to release from :trunk or :stable
    # @param version [String] the versin to release as
    def initialize(project, origin, version)
      @project = project
      @source = Source.new
      @archive_ = XzArchive.new
      @origin = origin
      @version = version

      # FIXME: this possibly should be logic inside Project itself?
      if project.vcs.is_a? Git
        project.vcs.branch = case origin
                             when :trunk
                               project.i18n_trunk
                             when :stable
                               project.i18n_stable
                             when :lts
                               project.i18n_lts
                             else
                               raise "Origin #{origin} unsupported. See readme."
                             end
      end

      source.target = "#{project.identifier}-#{version}"
    end

    # Get the source
    # FIXME: l10n and documentation have no test backing
    def get
      log_info 'Getting CI states.'
      check_ci!

      log_info "Getting source #{project.vcs}"
      play if ENV.key?('RELEASE_THE_BEAT')
      source.cleanup
      source.get(project.vcs)

      # FIXME: one would think that perhaps l10n could be disabled entirely
      log_info ' Getting translations...'
      # FIXME: why not pass project itself? Oo
      # FIXME: origin should be validated? technically optparse enforces proper values
      l10n = L10n.new(origin, project.identifier, project.i18n_path)
      l10n.get(source.target)

      log_info ' Getting documentation...'
      doc = DocumentationL10n.new(origin, project.identifier, project.i18n_path)
      doc.get(source.target)
    end

    # FIXME: archive is an attr and a method, lovely
    # Create the final archive file
    def archive
      log_info "Archiving source #{project.vcs}"
      source.clean(project.vcs)
      @archive_.directory = source.target
      @archive_.create
      @signature = ArchiveSigner.new.sign(@archive_)
    end

    def help
      return if Silencer.shutup?
      tar = archive_.filename
      sig = File.basename(@signature)

      uri = sysadmin_ticket(tar, sig)

      template = HashTemplate.new(tarball: tar, signature: sig, ticket_uri: uri)
      puts template.render("#{__dir__}/data/release_help.txt.erb")
    end

    private

    def sysadmin_ticket(tar, sig)
      title = "Publish #{tar}"
      sha256s = [sig, tar].collect { |x| `sha256sum #{x}`.strip }
      sha1s = [sig, tar].collect { |x| `sha1sum #{x}`.strip }
      template = HashTemplate.new(sha256s: sha256s, sha1s: sha1s, version: version)
      template_file = "#{__dir__}/data/ticket_description.txt.erb"
      description = template.render(template_file)
      sysadmin_ticket_uri(title: title, description: description)
    end

    def sysadmin_ticket_uri(**form_data)
      uri = URI.parse('https://phabricator.kde.org/maniphest/task/edit/form/2')
      uri.query = URI.encode_www_form(**form_data)
      uri
    end

    def warn_job_state(job)
      log_warn format(
        if job.building?
          'build.kde.org: %s is still building %s'
        else
          'build.kde.org: %s is not of sufficient quality %s'
        end, job.display_name, job.url
      )
    end

    def check_ci!
      jobs = Jenkins::Job.from_name_and_branch(project.identifier,
                                               project.vcs.branch)
      jobs.select! do |job|
        next false if job.sufficient_quality?
        warn_job_state(job)
        true
      end
      continue?(jobs)
    end

    def continue?(jobs)
      return if jobs.empty?
      loop do
        puts 'Continue despite unexpected job states? [y/n]' unless shutup?
        case gets.strip
        when 'y'
          break
        when 'n'
          abort
        end
      end
    end

    def play
      url = case ENV.fetch('RELEASE_THE_BEAT', '')
            when 'jam'
              'https://www.youtube.com/watch?v=EpkYIy6UhI4'
            else
              'https://www.youtube.com/watch?v=fNNdOFwQjcU'
            end
      return unless url
      play_thread(url)
    end

    def play_thread(url)
      Thread.new do
        loop do
          ret = system(*(%w[vlc --no-video --play-and-exit --intf dummy] << url),
                       pgroup: Process.pid)
          break unless ret
        end
      end
    end
  end
end
