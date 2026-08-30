"""
Cubren la parte del servicio que venia del consumer de WebSocket
(save_message y members_to_notify), que no se pudo caracterizar antes del
refactor
"""
from django.test import TestCase

from chats.models import Chat, ChatMembership, ChatMessage
from chats.services.chat_service import ChatService
from travels.tests.factories import create_request, create_travel, create_user


class ChatServiceSaveMessageTest(TestCase):

    def setUp(self):
        self.driver = create_user("driver")
        self.travel = create_travel(self.driver, num_seats=3, remaining_seats=3)
        self.chat = Chat.get_or_create_for_travel(self.travel)

    def test_save_message_creates_the_message_on_an_active_travel(self):
        message = ChatService.save_message(self.travel.pk, self.chat, self.driver, "Hola")

        self.assertIsNotNone(message)
        self.assertEqual(message.content, "Hola")
        self.assertEqual(ChatMessage.objects.filter(chat=self.chat).count(), 1)

    def test_save_message_returns_none_on_a_finished_travel(self):
        finished = create_travel(self.driver, num_seats=3, remaining_seats=3, state='fnd')
        chat = Chat.get_or_create_for_travel(finished)

        message = ChatService.save_message(finished.pk, chat, self.driver, "Hola")

        # None es la señal para que el consumer no difunda nada
        self.assertIsNone(message)
        self.assertEqual(ChatMessage.objects.filter(chat=chat).count(), 0)


class ChatServiceMembersToNotifyTest(TestCase):

    def setUp(self):
        self.driver = create_user("driver")
        self.first_passenger = create_user("passenger1")
        self.second_passenger = create_user("passenger2")

        self.travel = create_travel(self.driver, num_seats=4, remaining_seats=2)
        create_request(self.travel, self.first_passenger, 'accepted')
        create_request(self.travel, self.second_passenger, 'accepted')

        self.chat = Chat.get_or_create_for_travel(self.travel)

    def recipients(self, sender=None, present_ids=None):
        return ChatService.members_to_notify(
            self.chat, self.travel, sender or self.driver, present_ids or set()
        )

    def test_notifies_every_member_except_the_sender(self):
        recipients = self.recipients()

        self.assertCountEqual(
            [u.id for u in recipients],
            [self.first_passenger.id, self.second_passenger.id],
        )

    def test_does_not_notify_users_with_the_chat_open(self):
        recipients = self.recipients(present_ids={str(self.first_passenger.id)})

        self.assertEqual([u.id for u in recipients], [self.second_passenger.id])

    def test_does_not_notify_users_who_muted_the_chat(self):
        ChatMembership.objects.create(
            chat=self.chat, user=self.first_passenger, is_muted=True
        )

        recipients = self.recipients()

        self.assertEqual([u.id for u in recipients], [self.second_passenger.id])

    def test_does_not_notify_users_removed_from_the_chat(self):
        ChatMembership.objects.create(
            chat=self.chat, user=self.first_passenger, is_removed=True
        )

        recipients = self.recipients()

        self.assertEqual([u.id for u in recipients], [self.second_passenger.id])

    def test_archived_users_still_get_notified(self):
        """
        Archivar no silencia: solo mueve el chat de seccion
        """
        from django.utils import timezone

        ChatMembership.objects.create(
            chat=self.chat, user=self.first_passenger, archived_at=timezone.now()
        )

        recipients = self.recipients()

        self.assertIn(self.first_passenger.id, [u.id for u in recipients])

    def test_a_passenger_sending_notifies_the_driver(self):
        recipients = self.recipients(sender=self.first_passenger)

        self.assertCountEqual(
            [u.id for u in recipients],
            [self.driver.id, self.second_passenger.id],
        )
