# frozen_string_literal: true

class FanOutOnWriteService < BaseService
  # Push a status into home and mentions feeds
  # @param [Status] status
  def call(status)
    raise Mastodon::RaceConditionError if status.visibility.nil?

    deliver_to_self(status) if status.account.local?

    if status.direct_visibility?
      deliver_to_mentioned_followers(status)
    else
      deliver_to_followers(status)
    end

    return if status.account.silenced? || !status.public_visibility? || status.reblog?

    deliver_to_hashtags(status)

    return if status.reply? && status.in_reply_to_account_id != status.account_id

    deliver_to_public(status)
  end

  private

  def deliver_to_self(status)
    Rails.logger.debug "Delivering status #{status.id} to author"
    FeedManager.instance.push(:home, status.account, status)
  end

  def deliver_to_followers(status)
    Rails.logger.debug "Delivering status #{status.id} to followers"

    status.account.followers.where(domain: nil).joins(:user).where('users.current_sign_in_at > ?', 14.days.ago).select(:id).find_each do |follower|
      FeedInsertWorker.perform_async(status.id, follower.id)
    end
  end

  def deliver_to_mentioned_followers(status)
    Rails.logger.debug "Delivering status #{status.id} to mentioned followers"

    status.mentions.includes(:account).each do |mention|
      mentioned_account = mention.account
      next if !mentioned_account.local? || !mentioned_account.following?(status.account) || FeedManager.instance.filter?(:home, status, mention.account_id)
      FeedManager.instance.push(:home, mentioned_account, status)
    end
  end

  def deliver_to_hashtags(status)
    Rails.logger.debug "Delivering status #{status.id} to hashtags"

    payload = FeedManager.instance.inline_render(nil, 'api/v1/statuses/show', status)

    status.tags.pluck(:name).each do |hashtag|
      FeedManager.instance.broadcast("hashtag:#{hashtag}", event: 'update', payload: payload)
      FeedManager.instance.broadcast("hashtag:#{hashtag}:local", event: 'update', payload: payload) if status.account.local?
    end
  end

  def deliver_to_public(status)
    Rails.logger.debug "Delivering status #{status.id} to public timeline"

    payload = FeedManager.instance.inline_render(nil, 'api/v1/statuses/show', status)

    FeedManager.instance.broadcast(:public, event: 'update', payload: payload)
    FeedManager.instance.broadcast('public:local', event: 'update', payload: payload) if status.account.local?
  end
end
