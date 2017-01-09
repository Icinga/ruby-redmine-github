require 'spec_helper'
require 'github/issue'
require 'redmine'

describe Github::Issue do
  let :redmine_issue do
    Redmine::Issue.new(
      id:          1234,
      subject:     'Test',
      description: 'h1. Header1\n\nPlease make sure *our* test runs _well_!\ntest\ntest\n<pre>\nWEIRDCODE <test></pre>some text<pre>OTHERCODE</pre>',
      status:      { id: 1, name: 'New' },
      priority:    { id: 3, name: 'Normal' },
      tracker:     { id: 1, name: 'Bug' }
    )
    # TODO: categories
  end

  subject do
    Github::Issue.new(redmine_issue)
  end

  describe '.redmine_description' do
    it 'should convert simple RedMine to code' do
      expect(subject.description).to match(/^    /)
      #expect(subject.description).to match(/test\ntest/)
      #expect(subject.description).to match(/# Header1/)
      #expect(subject.description).to match(/\*\*our\*\*/)
      #expect(subject.description).to match(/_well_/)
      #expect(subject.description).to match(/```\nWEIRDCODE <test>\n```/)
    end
  end
end
