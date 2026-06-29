import os
from django.db.models.signals import pre_save, post_delete
from django.dispatch import receiver
from .models import Users


# Delete the old picture when it actualizes
@receiver(pre_save, sender=Users)
def delete_old_profile_pic(sender, instance, **kwargs):
    if not instance.pk:
        return  # new user, no profile picture

    try:
        old_user = Users.objects.get(pk=instance.pk)
    except Users.DoesNotExist:
        return

    old_file = old_user.profile_picture
    new_file = instance.profile_picture

    if old_file and old_file != new_file:
        if os.path.isfile(old_file.path):
            os.remove(old_file.path)


@receiver(post_delete, sender=Users)
def delete_profile_pic_on_delete(sender, instance, **kwargs):
    file = instance.profile_picture

    if file and os.path.isfile(file.path):
        os.remove(file.path)
