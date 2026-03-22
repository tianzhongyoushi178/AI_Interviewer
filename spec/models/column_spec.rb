require 'rails_helper'

RSpec.describe Column, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:parent).class_name('Column').optional }
    it { is_expected.to have_many(:children).class_name('Column') }
  end

  describe 'scopes' do
    before do
      @pillar = Column.create!(title: '親記事', article_type: 'pillar', code: 'pillar-1')
      @cluster = Column.create!(title: '子記事', article_type: 'cluster', code: 'cluster-1')
    end

    describe '.pillars' do
      it 'returns only pillar articles' do
        expect(Column.pillars).to include(@pillar)
        expect(Column.pillars).not_to include(@cluster)
      end
    end

    describe '.clusters' do
      it 'returns only cluster articles' do
        expect(Column.clusters).to include(@cluster)
        expect(Column.clusters).not_to include(@pillar)
      end
    end
  end

  describe '#pillar?' do
    it 'returns true for pillar type' do
      column = Column.new(article_type: 'pillar')
      expect(column.pillar?).to be true
    end

    it 'returns false for cluster type' do
      column = Column.new(article_type: 'cluster')
      expect(column.pillar?).to be false
    end
  end

  describe '#cluster?' do
    it 'returns true for cluster type' do
      column = Column.new(article_type: 'cluster')
      expect(column.cluster?).to be true
    end

    it 'returns false for pillar type' do
      column = Column.new(article_type: 'pillar')
      expect(column.cluster?).to be false
    end
  end

  describe '#cluster_full?' do
    it 'returns false when not a pillar' do
      column = Column.new(article_type: 'cluster')
      expect(column.cluster_full?).to be false
    end

    it 'returns false when cluster_limit is nil' do
      column = Column.create!(title: '親記事', article_type: 'pillar', code: 'pillar-limit-nil')
      expect(column.cluster_full?).to be false
    end

    it 'returns false when children count is below limit' do
      pillar = Column.create!(title: '親記事', article_type: 'pillar', code: 'pillar-not-full', cluster_limit: 3)
      Column.create!(title: '子1', article_type: 'cluster', code: 'child-1', parent: pillar)

      expect(pillar.cluster_full?).to be false
    end

    it 'returns true when children count reaches limit' do
      pillar = Column.create!(title: '親記事', article_type: 'pillar', code: 'pillar-full', cluster_limit: 2)
      Column.create!(title: '子1', article_type: 'cluster', code: 'child-full-1', parent: pillar)
      Column.create!(title: '子2', article_type: 'cluster', code: 'child-full-2', parent: pillar)

      expect(pillar.cluster_full?).to be true
    end
  end

  describe '#to_meta_tags' do
    it 'returns meta tag hash' do
      column = Column.new(title: 'テスト記事', keyword: 'テスト,記事', description: '説明文')
      meta = column.to_meta_tags

      expect(meta[:title]).to eq('テスト記事')
      expect(meta[:keyword]).to eq('テスト,記事')
      expect(meta[:description]).to eq('説明文')
    end
  end

  describe '#approved?' do
    it 'returns true when status is approved' do
      column = Column.new(status: 'approved')
      expect(column.approved?).to be true
    end

    it 'returns false when status is draft' do
      column = Column.new(status: 'draft')
      expect(column.approved?).to be false
    end
  end

  describe 'parent-child relationship' do
    it 'links children to parent' do
      pillar = Column.create!(title: '親記事', article_type: 'pillar', code: 'parent-rel')
      child = Column.create!(title: '子記事', article_type: 'cluster', code: 'child-rel', parent: pillar)

      expect(pillar.children).to include(child)
      expect(child.parent).to eq(pillar)
    end
  end

  describe 'constants' do
    it 'defines GENRE_MAPPING' do
      expect(Column::GENRE_MAPPING).to be_a(Hash)
      expect(Column::GENRE_MAPPING).to include('cargo', 'cleaning', 'security')
      expect(Column::GENRE_MAPPING).to be_frozen
    end

    it 'defines CATEGORY_IMAGES' do
      expect(Column::CATEGORY_IMAGES).to be_a(Hash)
      expect(Column::CATEGORY_IMAGES).to include('cargo', 'security', 'construction')
      expect(Column::CATEGORY_IMAGES).to be_frozen
    end
  end

  describe 'default values' do
    it 'defaults to draft status' do
      column = Column.new
      expect(column.status).to eq('draft')
    end

    it 'defaults to cluster article_type' do
      column = Column.new
      expect(column.article_type).to eq('cluster')
    end
  end
end
