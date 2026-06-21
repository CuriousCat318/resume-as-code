#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'yaml'

ROOT = File.expand_path('..', __dir__)
LOCALE = ENV.fetch('RESUME_LOCALE', 'en')
INPUT_PATH = ENV.fetch('RESUME_INPUT', File.join(ROOT, 'locales', "#{LOCALE}.yml"))
OUTPUT_PATH = ENV.fetch('RESUME_OUTPUT', File.join(ROOT, 'dist', 'pdf', "cv-#{LOCALE}-light.pdf"))

class SimplePdf
  PAGE_WIDTH = 612.0
  PAGE_HEIGHT = 792.0
  TOP_MARGIN = 42.0
  BOTTOM_MARGIN = 42.0
  LEFT_MARGIN = 46.0
  RIGHT_MARGIN = 46.0

  FONT_REGULAR = 'F1'
  FONT_BOLD = 'F2'

  attr_reader :pages

  def initialize
    @pages = []
    @content = +''
    @y = PAGE_HEIGHT - TOP_MARGIN
  end

  def save(path)
    finish_page
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, build_pdf)
  end

  def text(value, x:, y: @y, size: 9.0, font: FONT_REGULAR)
    clean = sanitize(value)
    @content << "BT /#{font} #{size} Tf 1 0 0 1 #{fmt(x)} #{fmt(y)} Tm (#{escape(clean)}) Tj ET\n"
  end

  def centered(value, y: @y, size: 10.0, font: FONT_REGULAR)
    width = approximate_width(value, size)
    text(value, x: (PAGE_WIDTH - width) / 2.0, y: y, size: size, font: font)
  end

  def line(x1:, y1:, x2:, y2:, width: 0.5)
    @content << "#{fmt(width)} w #{fmt(x1)} #{fmt(y1)} m #{fmt(x2)} #{fmt(y2)} l S\n"
  end

  def section(title)
    ensure_space(26)
    @y -= 12
    text(title.upcase, x: LEFT_MARGIN, y: @y, size: 9.5, font: FONT_BOLD)
    line(x1: LEFT_MARGIN, y1: @y - 4, x2: PAGE_WIDTH - RIGHT_MARGIN, y2: @y - 4)
    @y -= 16
  end

  def heading(left, right = nil, subtitle: nil)
    ensure_space(subtitle ? 32 : 22)
    text(left, x: LEFT_MARGIN, y: @y, size: 9.5, font: FONT_BOLD)

    if right && !right.empty?
      right_width = approximate_width(right, 9.0)
      text(right, x: PAGE_WIDTH - RIGHT_MARGIN - right_width, y: @y, size: 9.0, font: FONT_REGULAR)
    end

    @y -= 11

    if subtitle && !subtitle.empty?
      text(subtitle, x: LEFT_MARGIN, y: @y, size: 9.0, font: FONT_REGULAR)
      @y -= 9
    end
  end

  def paragraph(value, indent: 0.0, size: 8.5, leading: 10.0, width: content_width)
    wrap(value.to_s, width - indent, size).each do |line_text|
      ensure_space(leading)
      text(line_text, x: LEFT_MARGIN + indent, y: @y, size: size)
      @y -= leading
    end
  end

  def bullet(value, size: 8.4, leading: 9.7)
    lines = wrap(value.to_s, content_width - 16, size)
    lines.each_with_index do |line_text, index|
      ensure_space(leading)
      prefix = index.zero? ? '- ' : '  '
      text("#{prefix}#{line_text}", x: LEFT_MARGIN + 8, y: @y, size: size)
      @y -= leading
    end
  end

  def skill_line(label, values)
    paragraph("#{label}: #{Array(values).join(', ')}", size: 8.3, leading: 9.5)
  end

  def gap(amount)
    @y -= amount
  end

  def ensure_space(required)
    return if @y - required >= BOTTOM_MARGIN

    finish_page
  end

  private

  def content_width
    PAGE_WIDTH - LEFT_MARGIN - RIGHT_MARGIN
  end

  def finish_page
    return if @content.empty?

    @pages << @content
    @content = +''
    @y = PAGE_HEIGHT - TOP_MARGIN
  end

  def build_pdf
    objects = []
    objects << '<< /Type /Catalog /Pages 2 0 R >>'

    font_regular_id = 3
    font_bold_id = 4
    page_object_ids = []

    @pages.each_index do |index|
      page_object_ids << (5 + index * 2)
    end

    kids = page_object_ids.map { |id| "#{id} 0 R" }.join(' ')
    objects << "<< /Type /Pages /Kids [#{kids}] /Count #{@pages.length} >>"
    objects << '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'
    objects << '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>'

    @pages.each_with_index do |content, index|
      page_id = page_object_ids[index]
      content_id = page_id + 1
      resources = "<< /Font << /F1 #{font_regular_id} 0 R /F2 #{font_bold_id} 0 R >> >>"
      objects << "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 #{PAGE_WIDTH.to_i} #{PAGE_HEIGHT.to_i}] /Resources #{resources} /Contents #{content_id} 0 R >>"
      objects << "<< /Length #{content.bytesize} >>\nstream\n#{content}endstream"
    end

    write_objects(objects)
  end

  def write_objects(objects)
    pdf = +"%PDF-1.4\n"
    offsets = [0]

    objects.each_with_index do |object, index|
      offsets << pdf.bytesize
      pdf << "#{index + 1} 0 obj\n#{object}\nendobj\n"
    end

    xref_offset = pdf.bytesize
    pdf << "xref\n0 #{objects.length + 1}\n"
    pdf << "0000000000 65535 f \n"
    offsets[1..].each { |offset| pdf << format('%010d 00000 n ', offset) << "\n" }
    pdf << "trailer\n<< /Size #{objects.length + 1} /Root 1 0 R >>\n"
    pdf << "startxref\n#{xref_offset}\n%%EOF\n"
    pdf
  end

  def wrap(value, width, size)
    normalized = sanitize(value).gsub(/\s+/, ' ').strip
    return [''] if normalized.empty?

    max_chars = [(width / (size * 0.48)).floor, 20].max
    lines = []
    current = +''

    normalized.split.each do |word|
      candidate = current.empty? ? word : "#{current} #{word}"
      if candidate.length <= max_chars
        current = candidate
      else
        lines << current unless current.empty?
        current = word
      end
    end

    lines << current unless current.empty?
    lines
  end

  def approximate_width(value, size)
    sanitize(value).length * size * 0.48
  end

  def sanitize(value)
    value.to_s
         .tr("\u2018\u2019", "'")
         .tr("\u201C\u201D", '"')
         .tr("\u2013\u2014", '-')
         .gsub(/[^\x09\x0A\x0D\x20-\x7E]/, '')
  end

  def escape(value)
    value.gsub('\\', '\\\\\\').gsub('(', '\\(').gsub(')', '\\)')
  end

  def fmt(number)
    format('%.2f', number)
  end
end

def join_present(*values)
  values.compact.map(&:to_s).reject(&:empty?).join(' | ')
end

resume = YAML.load_file(INPUT_PATH)
profile = resume.fetch('profile')
pdf = SimplePdf.new

pdf.centered(profile.fetch('name'), size: 18, font: SimplePdf::FONT_BOLD)
pdf.gap(15)
pdf.centered(profile.fetch('title'), size: 11, font: SimplePdf::FONT_BOLD)
pdf.gap(13)
pdf.centered(join_present(profile['location'], profile['phone'], profile['email'], profile['linkedin']), size: 8.5)
pdf.gap(9)

pdf.section('Summary')
pdf.paragraph(profile['summary'], size: 8.6, leading: 9.8)

pdf.section('Skills')
skills = resume.fetch('skills')
pdf.skill_line('Languages', skills['languages'])
pdf.skill_line('Frontend', skills['frontend'])
pdf.skill_line('AWS Services', skills['aws_services'])
pdf.skill_line('Databases', skills['databases'])
pdf.skill_line('DevOps and Infra', skills['devops_and_infra'])
pdf.skill_line('Concepts', skills['concepts'])

pdf.section('Education')
Array(resume['education']).each do |item|
  pdf.heading(
    join_present(item['institution'], item['location']),
    item['graduation'],
    subtitle: item['degree']
  )
  pdf.bullet("Coursework: #{Array(item['coursework']).join(', ')}") if item['coursework']
  if item['teaching_assistant_roles']
    pdf.bullet("Teaching Assistant: #{Array(item['teaching_assistant_roles']).join(', ')} (#{item['teaching_assistant_dates']})")
  end
  pdf.gap(3)
end

pdf.section('Experience')
Array(resume['experience']).each do |item|
  pdf.heading(
    join_present(item['company'], item['location']),
    item['dates'],
    subtitle: item['title']
  )
  Array(item['bullets']).each { |bullet| pdf.bullet(bullet) }
  pdf.gap(5)
end

pdf.section('Key Projects')
Array(resume['projects']).each do |item|
  pdf.heading(item['name'])
  Array(item['bullets']).each { |bullet| pdf.bullet(bullet) }
  pdf.gap(3)
end

credentials = Array(resume['certifications_and_credentials'])
unless credentials.empty?
  pdf.section('Certifications and Credentials')
  pdf.paragraph(credentials.join(' | '), size: 8.5, leading: 10)
end

pdf.save(OUTPUT_PATH)
puts "Built #{OUTPUT_PATH}"
