# frozen_string_literal: true

class StreamEntry < ApplicationRecord
  include Paginable

  belongs_to :account, inverse_of: :stream_entries
  belongs_to :activity, polymorphic: true

  belongs_to :status, foreign_type: 'Status', foreign_key: 'activity_id', inverse_of: :stream_entry

  validates :account, :activity, presence: true

  STATUS_INCLUDES = [:account, :stream_entry, :media_attachments, :tags, mentions: :account, reblog: [:stream_entry, :account, mentions: :account], thread: [:stream_entry, :account]].freeze

  scope :with_includes, -> { includes(:account, status: STATUS_INCLUDES) }

  def object_type
    if orphaned?
      :activity
    else
      targeted? ? :activity : activity.object_type
    end
  end

  def verb
    orphaned? ? :delete : activity.verb
  end

  def targeted?
    [:follow, :request_friend, :authorize, :reject, :unfollow, :block, :unblock, :share, :favorite].include? verb
  end

  def target
    orphaned? ? nil : activity.target
  end

  def title
    orphaned? ? nil : activity.title
  end

  def content
    orphaned? ? nil : activity.content
  end

  def threaded?
    (verb == :favorite || object_type == :comment) && !thread.nil?
  end

  def thread
    orphaned? ? nil : activity.thread
  end

  def mentions
    activity.respond_to?(:mentions) ? activity.mentions.map(&:account) : []
  end

  def activity
    !new_record? ? send(activity_type.underscore) || super : super
  end

  private

  def orphaned?
    activity.nil?
  end
end
