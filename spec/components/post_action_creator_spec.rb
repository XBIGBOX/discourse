require 'rails_helper'
require 'post_action_creator'

describe PostActionCreator do
  let(:user) { Fabricate(:user) }
  let(:post) { Fabricate(:post) }
  let(:like_type_id) { PostActionType.types[:like] }

  describe 'perform' do
    it 'creates a post action' do
      result = PostActionCreator.new(user, post, like_type_id).perform
      expect(result.success).to eq(true)
      expect(result.post_action).to be_present
      expect(result.post_action.user).to eq(user)
      expect(result.post_action.post).to eq(post)
      expect(result.post_action.post_action_type_id).to eq(like_type_id)
    end

    it 'does not create an invalid post action' do
      result = PostActionCreator.new(user, nil, like_type_id).perform
      expect(result.failed?).to eq(true)
    end
  end

  context "flags" do
    it "will create a reviewable if one does not exist" do
      result = PostActionCreator.create(user, post, :inappropriate)
      expect(result.success?).to eq(true)

      reviewable = result.reviewable
      expect(reviewable).to be_pending
      expect(reviewable.created_by).to eq(user)
      expect(reviewable.type).to eq("ReviewableFlaggedPost")

      expect(reviewable.reviewable_scores.count).to eq(1)
      score = reviewable.reviewable_scores.find_by(user: user)
      expect(score).to be_present
    end

    context "existing reviewable" do
      let!(:reviewable) {
        PostActionCreator.create(Fabricate(:user), post, :inappropriate).reviewable
      }

      it "appends to an existing reviewable if exists" do
        result = PostActionCreator.create(user, post, :inappropriate)
        expect(result.success?).to eq(true)

        expect(result.reviewable).to eq(reviewable)
        expect(reviewable.reviewable_scores.count).to eq(2)
        score = reviewable.reviewable_scores.find_by(user: user)
        expect(score).to be_present
      end
    end
  end
end
