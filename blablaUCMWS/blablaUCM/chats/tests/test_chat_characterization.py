"""
Pruebas de CARACTERIZACION de los endpoints del chat

    GET    /api/v1/chats/
    GET    /api/v1/chats/{travel_id}/messages/
    POST   /api/v1/chats/{travel_id}/mute/
    POST   /api/v1/chats/{travel_id}/archive/
    POST   /api/v1/chats/{travel_id}/unarchive/
    DELETE /api/v1/chats/{travel_id}/

Se escriben ANTES de extraer la logica a ChatService. Como el resto de las de
caracterizacion, atacan por HTTP para seguir siendo validas sin tocar una linea despues del refactor
"""
import uuid

from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from api.errors import ErrorCodes
from chats.models import Chat, ChatMembership, ChatMessage
from travels.tests.factories import create_request, create_travel, create_user


class BaseChatTest(APITestCase):

    def setUp(self):
        self.driver = create_user("driver")
        self.passenger = create_user("passenger")
        self.travel = create_travel(self.driver, num_seats=3, remaining_seats=2)
        create_request(self.travel, self.passenger, 'accepted')

    def authenticate(self, user):
        self.client.force_authenticate(user=user)

    def chat(self, travel=None):
        return Chat.get_or_create_for_travel(travel or self.travel)

    def add_message(self, user, content="Hola"):
        return ChatMessage.objects.create(chat=self.chat(), user=user, content=content)


class ChatListTest(BaseChatTest):
    """GET /api/v1/chats/ ."""

    def list_chats(self, archived=None):
        url = "/api/v1/chats/"
        if archived is not None:
            url += f"?archived={'true' if archived else 'false'}"
        return self.client.get(url)

    def travel_ids(self, response):
        return {row['id'] for row in response.data['results']}

    def test_driver_sees_the_chat_of_their_travel(self):
        self.authenticate(self.driver)

        response = self.list_chats()

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn(str(self.travel.pk), self.travel_ids(response))

    def test_accepted_passenger_sees_the_chat(self):
        self.authenticate(self.passenger)

        response = self.list_chats()

        self.assertIn(str(self.travel.pk), self.travel_ids(response))

    def test_pending_passenger_does_not_see_the_chat(self):
        outsider = create_user("pending_user")
        create_request(self.travel, outsider, 'pending')
        self.authenticate(outsider)

        response = self.list_chats()

        self.assertNotIn(str(self.travel.pk), self.travel_ids(response))

    def test_removed_member_does_not_see_the_chat(self):
        ChatMembership.objects.create(chat=self.chat(), user=self.passenger, is_removed=True)
        self.authenticate(self.passenger)

        response = self.list_chats()

        self.assertNotIn(str(self.travel.pk), self.travel_ids(response))

    def test_archived_filter_separates_the_chats(self):
        ChatMembership.objects.create(
            chat=self.chat(), user=self.passenger, archived_at=timezone.now()
        )
        self.authenticate(self.passenger)

        self.assertNotIn(str(self.travel.pk), self.travel_ids(self.list_chats(archived=False)))
        self.assertIn(str(self.travel.pk), self.travel_ids(self.list_chats(archived=True)))

    def test_driver_cannot_leave_until_the_travel_is_finished(self):
        self.authenticate(self.driver)

        row = next(r for r in self.list_chats().data['results'] if r['id'] == str(self.travel.pk))

        self.assertFalse(row['can_leave'])

    def test_passenger_can_always_leave(self):
        self.authenticate(self.passenger)

        row = next(r for r in self.list_chats().data['results'] if r['id'] == str(self.travel.pk))

        self.assertTrue(row['can_leave'])

    def test_chats_with_messages_come_first(self):
        # Un segundo viaje sin mensajes, con fecha anterior
        other_travel = create_travel(self.driver, num_seats=3, remaining_seats=3)
        Chat.get_or_create_for_travel(other_travel)
        self.add_message(self.driver, "El ultimo mensaje")
        self.authenticate(self.driver)

        rows = self.list_chats().data['results']

        # El que tiene mensajes va primero, aunque el otro sea mas reciente
        self.assertEqual(rows[0]['id'], str(self.travel.pk))
        self.assertEqual(rows[0]['last_message'], "El ultimo mensaje")
        self.assertIsNone(
            next(r for r in rows if r['id'] == str(other_travel.pk))['last_message']
        )

    def test_deleted_messages_are_not_shown_as_last_message(self):
        message = self.add_message(self.driver, "Borrado")
        message.is_deleted = True
        message.save()
        self.authenticate(self.driver)

        row = next(r for r in self.list_chats().data['results'] if r['id'] == str(self.travel.pk))

        self.assertIsNone(row['last_message'])


class ChatMessagesTest(BaseChatTest):
    """GET /api/v1/chats/{travel_id}/messages/ ."""

    def get_messages(self, travel_id=None):
        return self.client.get(f"/api/v1/chats/{travel_id or self.travel.pk}/messages/")

    def test_member_gets_the_message_history(self):
        self.add_message(self.driver, "Primero")
        self.add_message(self.passenger, "Segundo")
        self.authenticate(self.passenger)

        response = self.get_messages()

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual([m['content'] for m in response.data['results']], ["Primero", "Segundo"])
        self.assertTrue(response.data['can_send'])

    def test_deleted_messages_are_not_returned(self):
        message = self.add_message(self.driver, "Borrado")
        message.is_deleted = True
        message.save()
        self.authenticate(self.driver)

        response = self.get_messages()

        self.assertEqual(response.data['results'], [])

    def test_non_member_gets_403(self):
        outsider = create_user("outsider")
        self.authenticate(outsider)

        response = self.get_messages()

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(response.data['error_code'], ErrorCodes.INSUFICIENT_CREDENTIALS)

    def test_unknown_travel_gets_404(self):
        self.authenticate(self.driver)

        response = self.get_messages(travel_id=uuid.uuid4())

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertEqual(response.data['error_code'], ErrorCodes.TRAVEL_DONT_EXIST)

    def test_can_send_is_false_when_the_travel_is_finished(self):
        finished = create_travel(self.driver, num_seats=3, remaining_seats=3, state='fnd')
        self.authenticate(self.driver)

        response = self.get_messages(travel_id=finished.pk)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertFalse(response.data['can_send'])


class ChatMuteAndArchiveTest(BaseChatTest):
    """POST .../mute/, .../archive/ y .../unarchive/ ."""

    def membership(self):
        return ChatMembership.objects.get(chat=self.chat(), user=self.passenger)

    def test_mute_and_unmute(self):
        self.authenticate(self.passenger)

        response = self.client.post(
            f"/api/v1/chats/{self.travel.pk}/mute/", {'muted': True}, format='json'
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['is_muted'])
        self.assertTrue(self.membership().is_muted)

        self.client.post(
            f"/api/v1/chats/{self.travel.pk}/mute/", {'muted': False}, format='json'
        )
        self.assertFalse(self.membership().is_muted)

    def test_archive_and_unarchive(self):
        self.authenticate(self.passenger)

        self.client.post(f"/api/v1/chats/{self.travel.pk}/archive/", {}, format='json')
        self.assertIsNotNone(self.membership().archived_at)

        self.client.post(f"/api/v1/chats/{self.travel.pk}/unarchive/", {}, format='json')
        self.assertIsNone(self.membership().archived_at)

    def test_non_member_cannot_mute(self):
        outsider = create_user("outsider")
        self.authenticate(outsider)

        response = self.client.post(
            f"/api/v1/chats/{self.travel.pk}/mute/", {'muted': True}, format='json'
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)


class LeaveChatTest(BaseChatTest):
    """DELETE /api/v1/chats/{travel_id}/ ."""

    def leave(self, travel_id=None):
        return self.client.delete(f"/api/v1/chats/{travel_id or self.travel.pk}/")

    def test_passenger_can_leave(self):
        self.authenticate(self.passenger)

        response = self.leave()

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        membership = ChatMembership.objects.get(chat=self.chat(), user=self.passenger)
        self.assertTrue(membership.is_removed)

    def test_driver_cannot_leave_before_the_travel_finishes(self):
        self.authenticate(self.driver)

        response = self.leave()

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data['error_code'], ErrorCodes.TRAVEL_ALREADY_STARTED)
        self.assertFalse(
            ChatMembership.objects.filter(
                chat=self.chat(), user=self.driver, is_removed=True
            ).exists()
        )

    def test_driver_can_leave_once_the_travel_is_finished(self):
        finished = create_travel(self.driver, num_seats=3, remaining_seats=3, state='fnd')
        self.authenticate(self.driver)

        response = self.leave(travel_id=finished.pk)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        membership = ChatMembership.objects.get(
            chat=Chat.get_or_create_for_travel(finished), user=self.driver
        )
        self.assertTrue(membership.is_removed)
