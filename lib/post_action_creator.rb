require_dependency 'has_errors'

class PostActionCreator
  class CreateResult
    include HasErrors

    attr_accessor :success, :post_action, :reviewable

    def initialize
      @success = false
    end

    def success?
      @success
    end

    def failed?
      !success
    end
  end

  def initialize(
    created_by,
    post,
    post_action_type_id,
    is_warning: false,
    message: nil,
    take_action: false,
    flag_topic: false
  )
    @created_by = created_by

    @post = post
    @post_action_type_id = post_action_type_id

    @is_warning = is_warning
    @take_action = take_action && guardian.is_staff?

    @message = message
    @flag_topic = flag_topic
  end

  # Shortcut for PostActionCreator.new(...).perform, also takes a key instead of an id
  def self.create(created_by, post, action_key, message: nil)
    new(created_by, post, PostActionType.types[action_key], message: message).perform
  end

  def perform
    result = CreateResult.new

    unless guardian.post_can_act?(
      @post,
      PostActionType.types[@post_action_type_id],
      opts: {
        is_warning: @is_warning,
        taken_actions: PostAction.counts_for([@post].compact, @created_by)[@post&.id]
      }
    )
      result.forbidden = true
      result.add_error(I18n.t("invalid_access"))
      return result
    end

    args = {}
    args[:message] = @message if @message.present?
    args[:is_warning] = @is_warning
    args[:take_action] = @take_action
    args[:flag_topic] = @flag_topic

    begin
      post_action = PostAction.act(@created_by, @post, @post_action_type_id, args)

      if post_action.blank? || post_action.errors.present?
        result.add_errors_from(post_action)
      else
        result.success = true
        result.post_action = post_action
        create_reviewable(result)
      end

    rescue PostAction::FailedToCreatePost => e
      result.add_errors_from(e)
    rescue PostAction::AlreadyActed
      # If the user already performed this action, it's proably due to a different browser tab
      # or non-debounced clicking. We can ignore.
      result.success = true
      result.post_action = PostAction.find_by(
        user: @created_by,
        post: @post,
        post_action_type_id: @post_action_type_id
      )
    end

    result
  end

private

  def create_reviewable(result)
    return unless PostActionType.notify_flag_type_ids.include?(@post_action_type_id)

    result.reviewable = ReviewableFlaggedPost.needs_review!(
      created_by: @created_by,
      target: @post,
      reviewable_by_moderator: true
    )
    result.reviewable.add_score(@created_by, @post_action_type_id)
  end

  def guardian
    @guardian ||= Guardian.new(@created_by)
  end

end
