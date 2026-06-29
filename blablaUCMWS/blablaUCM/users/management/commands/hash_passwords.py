from django.core.management.base import BaseCommand
from users.models import Users
from django.contrib.auth.hashers import is_password_usable


class Command(BaseCommand):
    help = 'Hash all plain-text passwords in the Users table'

    def handle(self, *args, **options):
        users = Users.objects.all()
        updated_count = 0
        
        for user in users:
            if user.password and not user.password.startswith('pbkdf2_sha256$'):
                # Password is plain text, hash it
                original_password = user.password
                user.set_password(original_password)
                user.save()
                updated_count += 1
                self.stdout.write(
                    self.style.SUCCESS(f'✓ Hashed password for user: {user.username}')
                )
        
        self.stdout.write(
            self.style.SUCCESS(f'\n✓ Successfully hashed {updated_count} passwords')
        )
