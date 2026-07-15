from rest_framework import serializers

from chats.models import ChatMessage

# Serializer para el modelo ChatMessage
class ChatMessageSerializer(serializers.ModelSerializer):
    user_id = serializers.CharField(source='user.id', read_only=True)
    username = serializers.CharField(source='user.username', read_only=True)
    timestamp = serializers.DateTimeField(source='created_at', read_only=True)

    class Meta:
        model = ChatMessage
        fields = ['id', 'user_id', 'username', 'content', 'timestamp']
