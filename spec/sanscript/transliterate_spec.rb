# frozen_string_literal: true

require "spec_helper"

describe Sanscript::Transliterate do
  brahmic_schemes = %i[bengali devanagari gujarati gurmukhi kannada malayalam
                       oriya tamil telugu]
  roman_schemes = %i[hk kh iast iso15919 itrans itrans_dravidian kolkata velthuis]
  all_schemes = brahmic_schemes + roman_schemes

  context ".schemes" do
    it { expect(described_class.schemes).to be_kind_of(Hash).and not_be_empty }
    all_schemes.each do |scheme|
      it { expect(described_class.schemes).to include(scheme) }
    end
  end

  context ".roman_scheme?" do
    all_schemes.each do |scheme|
      expectation = roman_schemes.include?(scheme) ? true : false
      desc = ":#{scheme} should be #{expectation}"
      it desc do
        expect(described_class.roman_scheme?(scheme)).to eq(expectation)
      end
    end
  end

  context ".brahmic_scheme?" do
    all_schemes.each do |scheme|
      expectation = brahmic_schemes.include?(scheme) ? true : false
      desc = ":#{scheme} should be #{expectation}"
      it desc do
        expect(described_class.brahmic_scheme?(scheme)).to eq(expectation)
      end
    end
  end

  context ".transliterate" do
    it "raises a SchemeNotSupported error if an unsupported source scheme is specified" do
      expect { described_class.transliterate("", :unknown, :hk) }
        .to raise_error(Sanscript::SchemeNotSupportedError)
    end
    it "raises a SchemeNotSupported error if an unsupported destination scheme is specified" do
      expect { described_class.transliterate("", :hk, :unknown) }
        .to raise_error(Sanscript::SchemeNotSupportedError)
    end
  end

  context "Devanagari" do
    from = :devanagari

    context "to ITRANS" do
      to = :itrans
      # include_examples("letter tests", from, to)
      # include_examples("text tests", from, to)
      it "Decomposed nukta letters" do
        # ideally should be: "qa Ka Ga za .Da .Dha fa Ya Ra" but still symmetric
        expect(described_class.transliterate("क़ ख़ ग़ ज़ ड़ ढ़ फ़ य़ ऱ", from, to)).to eq("qa Ka Ga za .Da .Dha fa Ya Ra")
      end
    end

  end
end